package io.github.gallopingdino.agenttabs;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.intellij.ide.util.PropertiesComponent;
import com.intellij.openapi.project.Project;
import com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTab;
import com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTabsManager;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

// Remembers which terminal tab of a project runs which agent session, so they can be resumed on the next open.
final class AgentTabsRecorder {
    record RecordedAgentTab(String tabName, String agent, String sessionId, String workingDirectory) {
    }

    private static final String STORAGE_KEY = "agentTabs.agentSessionTabs";

    // Shells die while a project closes; a recording made then would forget every tab.
    private static final Set<Project> closingProjects = Collections.newSetFromMap(new ConcurrentHashMap<>());

    private AgentTabsRecorder() {
    }

    static void recordBeforeClose(Project project) {
        AgentHubCli.readLiveSessions().ifPresent(liveSessions -> recordAgentTabs(project, liveSessions));
        closingProjects.add(project);
    }

    static void forgetClosedProject(Project project) {
        closingProjects.remove(project);
    }

    static void recordAgentTabs(Project project, List<AgentHubCli.LiveAgentSession> liveSessions) {
        if (project.isDisposed() || closingProjects.contains(project))
            return;

        JsonArray tabs = new JsonArray();
        for (TerminalToolWindowTab tab : TerminalToolWindowTabsManager.getInstance(project).getTabs()) {
            findSessionInTab(tab, liveSessions).ifPresent(session -> {
                JsonObject json = new JsonObject();
                json.addProperty("tabName", tab.getContent().getDisplayName());
                json.addProperty("agent", session.agent());
                json.addProperty("sessionId", session.sessionId());
                json.addProperty("workingDirectory", session.workingDirectory());
                tabs.add(json);
            });
        }
        PropertiesComponent.getInstance(project).setValue(STORAGE_KEY, tabs.toString());
    }

    static Optional<AgentHubCli.LiveAgentSession> findSessionInTab(TerminalToolWindowTab tab, List<AgentHubCli.LiveAgentSession> liveSessions) {
        Long shellPid = TerminalTabsUtils.findShellPid(tab);
        if (shellPid == null)
            return Optional.empty();

        Set<Long> tabPids = ProcessHandle.of(shellPid)
            .map(shell -> shell.descendants().map(ProcessHandle::pid).collect(Collectors.toSet()))
            .orElse(Set.of());
        return liveSessions.stream().filter(session -> tabPids.contains(session.pid())).findFirst();
    }

    static List<RecordedAgentTab> loadRecordedTabs(Project project) {
        String stored = PropertiesComponent.getInstance(project).getValue(STORAGE_KEY);
        List<RecordedAgentTab> tabs = new ArrayList<>();
        if (stored == null)
            return tabs;

        try {
            for (JsonElement element : JsonParser.parseString(stored).getAsJsonArray()) {
                JsonObject json = element.getAsJsonObject();
                tabs.add(new RecordedAgentTab(json.get("tabName").getAsString(), json.get("agent").getAsString(), json.get("sessionId").getAsString(), json.get("workingDirectory").getAsString()));
            }
        }
        catch (RuntimeException e) {
            tabs.clear();
        }
        return tabs;
    }
}
