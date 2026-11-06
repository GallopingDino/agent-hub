package io.github.gallopingdino.agenttabs;

import com.intellij.openapi.application.ApplicationManager;
import com.intellij.openapi.application.ModalityState;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.startup.ProjectActivity;
import com.intellij.openapi.util.Disposer;
import com.intellij.openapi.wm.ToolWindow;
import com.intellij.openapi.wm.ToolWindowManager;
import com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTab;
import com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTabsManager;
import com.intellij.util.concurrency.AppExecutorUtil;
import kotlin.Unit;
import kotlin.coroutines.Continuation;
import org.jetbrains.annotations.NotNull;

import java.util.List;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

// Resumes the Claude Code sessions a project had in its terminal tabs when it was last closed.
public final class ClaudeTabsRestorer implements ProjectActivity {
    private static final String TERMINAL_TOOL_WINDOW_ID = "Terminal";
    // Rider restores its terminal tabs, without their processes, only once the Terminal tool window builds its content.
    private static final long TERMINAL_LOAD_DELAY_SECONDS = 3;
    private static final long RESTORE_DELAY_SECONDS = 3;
    private static final long RECORD_INTERVAL_SECONDS = 60;

    @Override
    public Object execute(@NotNull Project project, @NotNull Continuation<? super Unit> continuation) {
        ScheduledExecutorService scheduler = AppExecutorUtil.getAppScheduledExecutorService();
        scheduler.schedule(() -> runOnEdt(project, () -> {
            loadTerminalTabs(project);
            scheduler.schedule(() -> runOnEdt(project, () -> {
                resumeRecordedSessions(project);
                startRecording(project);
            }), RESTORE_DELAY_SECONDS, TimeUnit.SECONDS);
        }), TERMINAL_LOAD_DELAY_SECONDS, TimeUnit.SECONDS);
        return Unit.INSTANCE;
    }

    private static void loadTerminalTabs(Project project) {
        if (ClaudeTabsRecorder.loadRecordedTabs(project).isEmpty())
            return;

        ToolWindow terminal = ToolWindowManager.getInstance(project).getToolWindow(TERMINAL_TOOL_WINDOW_ID);
        if (terminal != null)
            terminal.getContentManager();
    }

    private static void resumeRecordedSessions(Project project) {
        List<ClaudeTabsRecorder.RecordedClaudeTab> recordedTabs = ClaudeTabsRecorder.loadRecordedTabs(project);
        for (ClaudeTabsRecorder.RecordedClaudeTab recorded : recordedTabs) {
            if (ClaudeSessionFiles.isSessionRunning(recorded.sessionId()))
                continue;

            TerminalToolWindowTab tab = findIdleTab(project, recorded.tabName());
            if (tab == null) {
                tab = TerminalToolWindowTabsManager.getInstance(project)
                    .createTabBuilder()
                    .workingDirectory(recorded.workingDirectory())
                    .tabName(recorded.tabName())
                    .requestFocus(false)
                    .createTab();
            }
            tab.getView().createSendTextBuilder().shouldExecute().send("claude --resume " + recorded.sessionId());
        }
    }

    private static TerminalToolWindowTab findIdleTab(Project project, String tabName) {
        for (TerminalToolWindowTab tab : TerminalToolWindowTabsManager.getInstance(project).getTabs()) {
            if (tabName.equals(tab.getContent().getDisplayName()) == false)
                continue;

            Long shellPid = TerminalTabsUtils.findShellPid(tab);
            boolean isRunningClaude = shellPid != null && ClaudeSessionFiles.findSessionInProcessTree(shellPid).isPresent();
            if (isRunningClaude == false)
                return tab;
        }
        return null;
    }

    private static void startRecording(Project project) {
        ScheduledFuture<?> recording = AppExecutorUtil.getAppScheduledExecutorService().scheduleWithFixedDelay(
            () -> runOnEdt(project, () -> ClaudeTabsRecorder.recordClaudeTabs(project)), RECORD_INTERVAL_SECONDS, RECORD_INTERVAL_SECONDS, TimeUnit.SECONDS);
        Disposer.register(project, () -> recording.cancel(false));
    }

    private static void runOnEdt(Project project, Runnable action) {
        ApplicationManager.getApplication().invokeLater(action, ModalityState.any(), project.getDisposed());
    }
}
