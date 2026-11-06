package io.github.gallopingdino.agenttabs;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.TimeUnit;

// Asks the agent-hub CLI which agent sessions are running; it knows how to find both Claude Code and Codex sessions.
final class AgentHubCli {
    record LiveAgentSession(String agent, long pid, String sessionId, String workingDirectory) {
    }

    private static final Path EXECUTABLE = Path.of(System.getProperty("user.home"), ".local", "bin", "agent-hub");
    private static final long TIMEOUT_SECONDS = 5;

    private AgentHubCli() {
    }

    static boolean isInstalled() {
        return Files.isExecutable(EXECUTABLE);
    }

    // Empty when the CLI is missing or fails, so callers never mistake a failure for "no sessions".
    static Optional<List<LiveAgentSession>> readLiveSessions() {
        if (isInstalled() == false)
            return Optional.empty();

        List<LiveAgentSession> sessions = new ArrayList<>();
        try {
            Process process = new ProcessBuilder(EXECUTABLE.toString(), "sessions", "--json").redirectErrorStream(false).start();
            process.getOutputStream().close();
            String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            if (process.waitFor(TIMEOUT_SECONDS, TimeUnit.SECONDS) == false || process.exitValue() != 0) {
                process.destroyForcibly();
                return Optional.empty();
            }

            for (JsonElement element : JsonParser.parseString(output).getAsJsonArray()) {
                JsonObject json = element.getAsJsonObject();
                sessions.add(new LiveAgentSession(json.get("agent").getAsString(), json.get("pid").getAsLong(), json.get("sessionId").getAsString(), json.get("workingDirectory").getAsString()));
            }
        }
        catch (IOException | InterruptedException | RuntimeException e) {
            return Optional.empty();
        }
        return Optional.of(sessions);
    }

    static String buildResumeCommand(String agent, String sessionId) {
        return switch (agent) {
            case "codex" -> "codex resume " + sessionId;
            default -> "claude --resume " + sessionId;
        };
    }
}
