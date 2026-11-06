package io.github.gallopingdino.agenttabs;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.stream.Stream;

// Claude Code writes ~/.claude/sessions/<pid>.json for every running interactive session.
final class ClaudeSessionFiles {
    record ClaudeSession(String sessionId, String workingDirectory) {
    }

    private static final Path SESSIONS_DIRECTORY = Path.of(System.getProperty("user.home"), ".claude", "sessions");

    private ClaudeSessionFiles() {
    }

    static Optional<ClaudeSession> findSessionInProcessTree(long rootPid) {
        Optional<ProcessHandle> root = ProcessHandle.of(rootPid);
        if (root.isEmpty())
            return Optional.empty();

        return root.get().descendants()
            .map(process -> readSessionOfProcess(process.pid()))
            .flatMap(Optional::stream)
            .findFirst();
    }

    static boolean isSessionRunning(String sessionId) {
        try (Stream<Path> files = Files.list(SESSIONS_DIRECTORY)) {
            return files
                .map(ClaudeSessionFiles::readSessionFile)
                .flatMap(Optional::stream)
                .anyMatch(session -> session.sessionId().equals(sessionId));
        }
        catch (IOException e) {
            return false;
        }
    }

    private static Optional<ClaudeSession> readSessionOfProcess(long pid) {
        return readSessionFile(SESSIONS_DIRECTORY.resolve(pid + ".json"));
    }

    private static Optional<ClaudeSession> readSessionFile(Path file) {
        try {
            JsonObject json = JsonParser.parseString(Files.readString(file)).getAsJsonObject();
            if ("interactive".equals(readString(json, "kind")) == false)
                return Optional.empty();

            String sessionId = readString(json, "sessionId");
            String workingDirectory = readString(json, "cwd");
            if (sessionId == null || workingDirectory == null)
                return Optional.empty();

            return Optional.of(new ClaudeSession(sessionId, workingDirectory));
        }
        catch (IOException | RuntimeException e) {
            return Optional.empty();
        }
    }

    private static String readString(JsonObject json, String key) {
        JsonElement value = json.get(key);
        return value != null && value.isJsonPrimitive() ? value.getAsString() : null;
    }
}
