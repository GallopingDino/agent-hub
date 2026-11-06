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
import java.util.Optional;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

// Resumes the agent sessions a project had in its terminal tabs when it was last closed.
public final class AgentTabsRestorer implements ProjectActivity {
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
            scheduler.schedule(() -> {
                Optional<List<AgentHubCli.LiveAgentSession>> liveSessions = AgentHubCli.readLiveSessions();
                runOnEdt(project, () -> {
                    liveSessions.ifPresent(sessions -> resumeRecordedSessions(project, sessions));
                    startRecording(project);
                });
            }, RESTORE_DELAY_SECONDS, TimeUnit.SECONDS);
        }), TERMINAL_LOAD_DELAY_SECONDS, TimeUnit.SECONDS);
        return Unit.INSTANCE;
    }

    private static void loadTerminalTabs(Project project) {
        if (AgentTabsRecorder.loadRecordedTabs(project).isEmpty())
            return;

        ToolWindow terminal = ToolWindowManager.getInstance(project).getToolWindow(TERMINAL_TOOL_WINDOW_ID);
        if (terminal != null)
            terminal.getContentManager();
    }

    private static void resumeRecordedSessions(Project project, List<AgentHubCli.LiveAgentSession> liveSessions) {
        for (AgentTabsRecorder.RecordedAgentTab recorded : AgentTabsRecorder.loadRecordedTabs(project)) {
            boolean isAlreadyRunning = liveSessions.stream().anyMatch(session -> session.sessionId().equals(recorded.sessionId()));
            if (isAlreadyRunning)
                continue;

            TerminalToolWindowTab tab = findIdleTab(project, recorded.tabName(), liveSessions);
            if (tab == null) {
                tab = TerminalToolWindowTabsManager.getInstance(project)
                    .createTabBuilder()
                    .workingDirectory(recorded.workingDirectory())
                    .tabName(recorded.tabName())
                    .requestFocus(false)
                    .createTab();
            }
            tab.getView().createSendTextBuilder().shouldExecute().send(AgentHubCli.buildResumeCommand(recorded.agent(), recorded.sessionId()));
        }
    }

    private static TerminalToolWindowTab findIdleTab(Project project, String tabName, List<AgentHubCli.LiveAgentSession> liveSessions) {
        for (TerminalToolWindowTab tab : TerminalToolWindowTabsManager.getInstance(project).getTabs()) {
            if (tabName.equals(tab.getContent().getDisplayName()) && AgentTabsRecorder.findSessionInTab(tab, liveSessions).isEmpty())
                return tab;
        }
        return null;
    }

    // The CLI runs off the UI thread; only reading the tabs needs it.
    private static void startRecording(Project project) {
        ScheduledFuture<?> recording = AppExecutorUtil.getAppScheduledExecutorService().scheduleWithFixedDelay(() -> {
            AgentHubCli.readLiveSessions().ifPresent(liveSessions -> runOnEdt(project, () -> AgentTabsRecorder.recordAgentTabs(project, liveSessions)));
        }, RECORD_INTERVAL_SECONDS, RECORD_INTERVAL_SECONDS, TimeUnit.SECONDS);
        Disposer.register(project, () -> recording.cancel(false));
    }

    private static void runOnEdt(Project project, Runnable action) {
        ApplicationManager.getApplication().invokeLater(action, ModalityState.any(), project.getDisposed());
    }
}
