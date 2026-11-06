package io.github.gallopingdino.agenttabs;

import com.intellij.openapi.project.Project;
import com.intellij.openapi.project.ProjectManagerListener;
import org.jetbrains.annotations.NotNull;

public final class AgentTabsCloseListener implements ProjectManagerListener {
    @Override
    public void projectClosing(@NotNull Project project) {
        AgentTabsRecorder.recordBeforeClose(project);
    }

    @Override
    public void projectClosed(@NotNull Project project) {
        AgentTabsRecorder.forgetClosedProject(project);
    }
}
