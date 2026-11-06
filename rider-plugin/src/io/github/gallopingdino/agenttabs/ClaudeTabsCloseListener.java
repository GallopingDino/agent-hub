package io.github.gallopingdino.agenttabs;

import com.intellij.openapi.project.Project;
import com.intellij.openapi.project.ProjectManagerListener;
import org.jetbrains.annotations.NotNull;

public final class ClaudeTabsCloseListener implements ProjectManagerListener {
    @Override
    public void projectClosing(@NotNull Project project) {
        ClaudeTabsRecorder.recordBeforeClose(project);
    }

    @Override
    public void projectClosed(@NotNull Project project) {
        ClaudeTabsRecorder.forgetClosedProject(project);
    }
}
