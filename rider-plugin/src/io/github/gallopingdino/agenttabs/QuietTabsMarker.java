package io.github.gallopingdino.agenttabs;

import com.intellij.openapi.application.ApplicationManager;
import com.intellij.openapi.application.ModalityState;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.project.ProjectManager;
import com.intellij.openapi.util.Key;
import com.intellij.openapi.wm.ToolWindow;
import com.intellij.openapi.wm.ToolWindowManager;
import com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTab;
import com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTabsManager;
import com.intellij.ui.content.Content;
import com.intellij.ui.content.ContentManager;
import com.intellij.ui.content.ContentManagerEvent;
import com.intellij.ui.content.ContentManagerListener;
import com.intellij.util.concurrency.AppExecutorUtil;
import org.jetbrains.annotations.NotNull;

import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.WeakHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

// Rider asks before closing a terminal tab with a running process, and an agent always is one. A tab whose agent is
// idle or inactive gets the platform's "temporarily removed" mark, which lets Rider close it without asking.
final class QuietTabsMarker {
    private static final String TERMINAL_TOOL_WINDOW_ID = "Terminal";
    private static final Set<String> QUIET_STATES = Set.of("idle", "stale");
    private static final long MARK_INTERVAL_SECONDS = 3;
    private static final Key<Boolean> IS_MARKED_QUIET_KEY = Key.create("agentTabs.isMarkedQuiet");
    private static final AtomicBoolean isWatching = new AtomicBoolean(false);
    // Read and written on the UI thread only; a split terminal pane has a content manager of its own.
    private static final Set<ContentManager> watchedContentManagers = Collections.newSetFromMap(new WeakHashMap<>());

    private QuietTabsMarker() {
    }

    // A failed CLI call reads as "no quiet agents", so a tab never stays marked on stale information.
    static void startWatching() {
        if (isWatching.compareAndSet(false, true) == false)
            return;

        AppExecutorUtil.getAppScheduledExecutorService().scheduleWithFixedDelay(() -> {
            List<AgentHubCli.LiveAgentSession> liveSessions = AgentHubCli.readLiveSessions().orElse(List.of());
            ApplicationManager.getApplication().invokeLater(() -> markQuietTabs(liveSessions), ModalityState.any());
        }, MARK_INTERVAL_SECONDS, MARK_INTERVAL_SECONDS, TimeUnit.SECONDS);
    }

    private static void markQuietTabs(List<AgentHubCli.LiveAgentSession> liveSessions) {
        for (Project project : ProjectManager.getInstance().getOpenProjects()) {
            if (project.isDisposed())
                continue;

            for (TerminalToolWindowTab tab : TerminalToolWindowTabsManager.getInstance(project).getTabs()) {
                boolean isQuiet = AgentTabsRecorder.findSessionInTab(tab, liveSessions).map(session -> QUIET_STATES.contains(session.state())).orElse(false);
                updateMark(project, tab.getContent(), isQuiet);
            }
        }
    }

    // Only a mark set here is lifted: Rider sets the same key itself while it moves a tab between panes.
    private static void updateMark(Project project, Content content, boolean isQuiet) {
        if (isQuiet) {
            content.putUserData(Content.TEMPORARY_REMOVED_KEY, true);
            content.putUserData(IS_MARKED_QUIET_KEY, true);
            watchRemovals(project, content.getManager());
        }
        else if (Boolean.TRUE.equals(content.getUserData(IS_MARKED_QUIET_KEY))) {
            content.putUserData(Content.TEMPORARY_REMOVED_KEY, null);
            content.putUserData(IS_MARKED_QUIET_KEY, null);
        }
    }

    // The mark also stops Rider from hiding the Terminal tool window when its last tab closes, so that is done here.
    private static void watchRemovals(Project project, ContentManager contentManager) {
        if (contentManager == null || watchedContentManagers.add(contentManager) == false)
            return;

        contentManager.addContentManagerListener(new ContentManagerListener() {
            @Override
            public void contentRemoved(@NotNull ContentManagerEvent event) {
                if (Boolean.TRUE.equals(event.getContent().getUserData(IS_MARKED_QUIET_KEY)) && contentManager.isEmpty())
                    hideTerminal(project);
            }
        });
    }

    private static void hideTerminal(Project project) {
        ToolWindow terminal = ToolWindowManager.getInstance(project).getToolWindow(TERMINAL_TOOL_WINDOW_ID);
        if (terminal != null)
            terminal.hide();
    }
}
