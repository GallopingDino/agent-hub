package com.kingbirdgames.agenttabs;

import com.intellij.openapi.application.ApplicationManager;
import com.intellij.openapi.application.ModalityState;
import com.intellij.openapi.project.Project;
import io.netty.channel.ChannelHandlerContext;
import io.netty.handler.codec.http.EmptyHttpHeaders;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.HttpHeaderNames;
import io.netty.handler.codec.http.HttpMethod;
import io.netty.handler.codec.http.QueryStringDecoder;
import org.jetbrains.ide.RestService;
import org.jetbrains.plugins.terminal.view.TerminalSendTextBuilder;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

public final class AgentTabsRestService extends RestService {
    @Override
    protected String getServiceName() {
        return "agent-tabs";
    }

    @Override
    protected boolean isMethodSupported(HttpMethod method) {
        return method == HttpMethod.GET;
    }

    // Browser pages always send Origin; only local command-line clients may call this API.
    @Override
    protected boolean isHostTrusted(FullHttpRequest request, QueryStringDecoder urlDecoder) {
        return request.headers().contains(HttpHeaderNames.ORIGIN) == false;
    }

    @Override
    public String execute(QueryStringDecoder urlDecoder, FullHttpRequest request, ChannelHandlerContext context) {
        String path = urlDecoder.path();
        String action = path.substring(path.lastIndexOf('/') + 1);

        AtomicReference<String> json = new AtomicReference<>();
        ApplicationManager.getApplication().invokeAndWait(() -> json.set(runAction(action, urlDecoder)), ModalityState.any());

        sendData(json.get().getBytes(StandardCharsets.UTF_8), "result.json", request, context.channel(), EmptyHttpHeaders.INSTANCE);
        return null;
    }

    private static String runAction(String action, QueryStringDecoder urlDecoder) {
        try {
            return switch (action) {
                case "list", "agent-tabs" -> TerminalTabsUtils.buildTabsJson();
                case "focus" -> focus(urlDecoder);
                case "open" -> open(urlDecoder);
                case "open-files" -> openFiles(urlDecoder);
                case "send-text" -> sendText(urlDecoder);
                default -> error("unknown action '" + action + "', expected list, focus, open, open-files or send-text");
            };
        }
        catch (RuntimeException e) {
            return error(e.toString());
        }
    }

    private static String focus(QueryStringDecoder urlDecoder) {
        String pid = findParameter(urlDecoder, "pid");
        String project = findParameter(urlDecoder, "project");
        String tab = findParameter(urlDecoder, "tab");

        TerminalTabsUtils.TabLocation location = null;
        if (pid != null)
            location = TerminalTabsUtils.findTabOwningProcess(Long.parseLong(pid));
        if (location == null && project != null && tab != null)
            location = TerminalTabsUtils.findTabByName(project, tab);
        if (location == null)
            return error("no terminal tab found for pid=" + pid + ", project=" + project + ", tab=" + tab);

        TerminalTabsUtils.focusTab(location);
        return describe(location);
    }

    private static String open(QueryStringDecoder urlDecoder) {
        String projectPath = findParameter(urlDecoder, "project");
        if (projectPath == null)
            return error("parameter 'project' is required");

        Project project = TerminalTabsUtils.findOpenProject(projectPath);
        if (project == null)
            return error("project is not open in Rider: " + projectPath);

        String directory = findParameter(urlDecoder, "dir");
        String workingDirectory = directory != null ? directory : project.getBasePath();
        TerminalTabsUtils.TabLocation location = TerminalTabsUtils.openTab(project, workingDirectory, findParameter(urlDecoder, "name"), findParameter(urlDecoder, "command"));
        return describe(location);
    }

    private static String openFiles(QueryStringDecoder urlDecoder) {
        String projectPath = findParameter(urlDecoder, "project");
        List<String> paths = urlDecoder.parameters().get("path");
        if (projectPath == null || paths == null || paths.isEmpty())
            return error("parameters 'project' and at least one 'path' are required");

        Project project = TerminalTabsUtils.findOpenProject(projectPath);
        if (project == null)
            return error("project is not open in Rider: " + projectPath);

        int openedCount = TerminalTabsUtils.openFiles(project, paths);
        return "{\"ok\":true,\"opened\":" + openedCount + "}";
    }

    private static String sendText(QueryStringDecoder urlDecoder) {
        String pid = findParameter(urlDecoder, "pid");
        String text = findParameter(urlDecoder, "text");
        if (pid == null || text == null || text.isEmpty())
            return error("parameters 'pid' and 'text' are required");

        TerminalTabsUtils.TabLocation location = TerminalTabsUtils.findTabOwningProcess(Long.parseLong(pid));
        if (location == null)
            return error("no terminal tab found for pid=" + pid);

        TerminalSendTextBuilder builder = location.tab().getView().createSendTextBuilder();
        if ("false".equals(findParameter(urlDecoder, "execute")) == false)
            builder = builder.shouldExecute();
        builder.send(text);
        return describe(location);
    }

    private static String describe(TerminalTabsUtils.TabLocation location) {
        return "{\"ok\":true,\"project\":" + TerminalTabsUtils.quote(location.project().getBasePath())
            + ",\"tab\":" + TerminalTabsUtils.quote(location.tab().getContent().getDisplayName()) + "}";
    }

    private static String error(String message) {
        return "{\"ok\":false,\"error\":" + TerminalTabsUtils.quote(message) + "}";
    }

    private static String findParameter(QueryStringDecoder urlDecoder, String name) {
        List<String> values = urlDecoder.parameters().get(name);
        return values == null || values.isEmpty() ? null : values.get(0);
    }
}
