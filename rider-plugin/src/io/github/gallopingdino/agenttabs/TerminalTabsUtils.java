package io.github.gallopingdino.agenttabs;

import com.intellij.ide.impl.ProjectUtil;
import com.intellij.openapi.fileEditor.FileEditorManager;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.project.ProjectManager;
import com.intellij.openapi.vfs.LocalFileSystem;
import com.intellij.openapi.vfs.VirtualFile;
import com.intellij.openapi.wm.ToolWindow;
import com.intellij.openapi.wm.ToolWindowManager;
import com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTab;
import com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTabsManager;
import com.intellij.ui.content.Content;
import com.intellij.ui.content.ContentManager;
import kotlinx.coroutines.Deferred;
import org.jetbrains.plugins.terminal.session.TerminalStartupOptions;

import java.nio.file.Path;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

final class TerminalTabsUtils {
    private static final String TERMINAL_TOOL_WINDOW_ID = "Terminal";

    record TabLocation(Project project, TerminalToolWindowTab tab) {
    }

    private TerminalTabsUtils() {
    }

    static String buildTabsJson() {
        StringBuilder json = new StringBuilder("[");
        for (Project project : ProjectManager.getInstance().getOpenProjects()) {
            for (TerminalToolWindowTab tab : TerminalToolWindowTabsManager.getInstance(project).getTabs()) {
                if (json.length() > 1)
                    json.append(',');

                Long shellPid = findShellPid(tab);
                json.append("{\"project\":").append(quote(project.getBasePath()))
                    .append(",\"tab\":").append(quote(tab.getContent().getDisplayName()))
                    .append(",\"shellPid\":").append(shellPid == null ? "null" : shellPid.toString())
                    .append(",\"cwd\":").append(quote(tab.getView().getCurrentDirectory()))
                    .append('}');
            }
        }
        return json.append(']').toString();
    }

    static TabLocation findTabOwningProcess(long pid) {
        Set<Long> ancestorPids = collectAncestorPids(pid);
        for (Project project : ProjectManager.getInstance().getOpenProjects()) {
            for (TerminalToolWindowTab tab : TerminalToolWindowTabsManager.getInstance(project).getTabs()) {
                Long shellPid = findShellPid(tab);
                if (shellPid != null && ancestorPids.contains(shellPid))
                    return new TabLocation(project, tab);
            }
        }
        return null;
    }

    static TabLocation findTabByName(String projectPath, String tabName) {
        Project project = findOpenProject(projectPath);
        if (project == null)
            return null;

        for (TerminalToolWindowTab tab : TerminalToolWindowTabsManager.getInstance(project).getTabs()) {
            if (tabName.equals(tab.getContent().getDisplayName()))
                return new TabLocation(project, tab);
        }
        return null;
    }

    static Project findOpenProject(String projectPath) {
        Path wanted = Path.of(projectPath).toAbsolutePath().normalize();
        for (Project project : ProjectManager.getInstance().getOpenProjects()) {
            String basePath = project.getBasePath();
            if (basePath != null && Path.of(basePath).toAbsolutePath().normalize().equals(wanted))
                return project;
        }
        return null;
    }

    static void focusTab(TabLocation location) {
        ProjectUtil.focusProjectWindow(location.project(), true);

        Content content = location.tab().getContent();
        ContentManager contentManager = content.getManager();
        ToolWindow toolWindow = ToolWindowManager.getInstance(location.project()).getToolWindow(TERMINAL_TOOL_WINDOW_ID);
        if (toolWindow == null)
            return;

        toolWindow.activate(() -> {
            if (contentManager != null)
                contentManager.setSelectedContent(content, true);
        }, true, true);
    }

    static TabLocation openTab(Project project, String workingDirectory, String tabName, String command) {
        TerminalToolWindowTab tab = TerminalToolWindowTabsManager.getInstance(project)
            .createTabBuilder()
            .workingDirectory(workingDirectory)
            .tabName(tabName)
            .requestFocus(true)
            .createTab();

        TabLocation location = new TabLocation(project, tab);
        focusTab(location);

        if (command != null && command.isBlank() == false)
            tab.getView().createSendTextBuilder().shouldExecute().send(command);

        return location;
    }

    static int openFiles(Project project, List<String> paths) {
        ProjectUtil.focusProjectWindow(project, true);

        FileEditorManager editorManager = FileEditorManager.getInstance(project);
        int openedCount = 0;
        for (String path : paths) {
            VirtualFile file = LocalFileSystem.getInstance().refreshAndFindFileByPath(path);
            if (file == null)
                continue;

            editorManager.openFile(file, true);
            openedCount++;
        }
        return openedCount;
    }

    static String quote(String value) {
        if (value == null)
            return "null";

        StringBuilder quoted = new StringBuilder("\"");
        for (char c : value.toCharArray()) {
            switch (c) {
                case '"' -> quoted.append("\\\"");
                case '\\' -> quoted.append("\\\\");
                case '\n' -> quoted.append("\\n");
                case '\r' -> quoted.append("\\r");
                case '\t' -> quoted.append("\\t");
                default -> {
                    if (c < 0x20)
                        quoted.append(String.format("\\u%04x", (int) c));
                    else
                        quoted.append(c);
                }
            }
        }
        return quoted.append('"').toString();
    }

    static Long findShellPid(TerminalToolWindowTab tab) {
        Deferred<TerminalStartupOptions> startupOptions = tab.getView().getStartupOptionsDeferred();
        if (startupOptions.isCompleted() == false)
            return null;

        try {
            return startupOptions.getCompleted().getPid();
        }
        catch (RuntimeException e) {
            return null;
        }
    }

    private static Set<Long> collectAncestorPids(long pid) {
        Set<Long> pids = new HashSet<>();
        Optional<ProcessHandle> process = ProcessHandle.of(pid);
        while (process.isPresent()) {
            pids.add(process.get().pid());
            process = process.get().parent();
        }
        return pids;
    }
}
