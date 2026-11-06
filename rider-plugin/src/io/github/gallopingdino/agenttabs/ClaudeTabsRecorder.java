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
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

// Remembers which terminal tab of a project runs which Claude Code session, so they can be resumed on the next open.
final class ClaudeTabsRecorder {
    record RecordedClaudeTab(String tabName, String sessionId, String workingDirectory) {
    }

    private static final String STORAGE_KEY = "agentTabs.claudeTabs";

    // Shells die while a project closes; a recording made then would forget every tab.
    private static final Set<Project> closingProjects = Collections.newSetFromMap(new ConcurrentHashMap<>());

    private ClaudeTabsRecorder() {
    }

    static void recordBeforeClose(Project project) {
        recordClaudeTabs(project);
        closingProjects.add(project);
    }

    static void forgetClosedProject(Project project) {
        closingProjects.remove(project);
    }

    static void recordClaudeTabs(Project project) {
        if (project.isDisposed() || closingProjects.contains(project))
            return;

        JsonArray tabs = new JsonArray();
        for (TerminalToolWindowTab tab : TerminalToolWindowTabsManager.getInstance(project).getTabs()) {
            Long shellPid = TerminalTabsUtils.findShellPid(tab);
            if (shellPid == null)
                continue;

            ClaudeSessionFiles.findSessionInProcessTree(shellPid).ifPresent(session -> {
                JsonObject json = new JsonObject();
                json.addProperty("tabName", tab.getContent().getDisplayName());
                json.addProperty("sessionId", session.sessionId());
                json.addProperty("workingDirectory", session.workingDirectory());
                tabs.add(json);
            });
        }
        PropertiesComponent.getInstance(project).setValue(STORAGE_KEY, tabs.toString());
    }

    static List<RecordedClaudeTab> loadRecordedTabs(Project project) {
        String stored = PropertiesComponent.getInstance(project).getValue(STORAGE_KEY);
        List<RecordedClaudeTab> tabs = new ArrayList<>();
        if (stored == null)
            return tabs;

        try {
            for (JsonElement element : JsonParser.parseString(stored).getAsJsonArray()) {
                JsonObject json = element.getAsJsonObject();
                tabs.add(new RecordedClaudeTab(json.get("tabName").getAsString(), json.get("sessionId").getAsString(), json.get("workingDirectory").getAsString()));
            }
        }
        catch (RuntimeException e) {
            tabs.clear();
        }
        return tabs;
    }
}
