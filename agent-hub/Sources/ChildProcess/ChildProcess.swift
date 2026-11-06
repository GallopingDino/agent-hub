import Foundation

public struct ChildProcessResult {
    public let exitStatus: Int32
    public let output: Data
    public let errorOutput: Data

    public var isSuccess: Bool { exitStatus == 0 }
}

// Foundation's Process costs ~70 ms per launch; posix_spawn costs ~2 ms.
public enum ChildProcess {
    public static func run(_ executable: String, _ arguments: [String], workingDirectory: String? = nil) -> ChildProcessResult? {
        var outputPipe: [Int32] = [0, 0]
        var errorPipe: [Int32] = [0, 0]
        guard pipe(&outputPipe) == 0 else { return nil }
        guard pipe(&errorPipe) == 0 else {
            outputPipe.forEach { close($0) }
            return nil
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], 1)
        posix_spawn_file_actions_adddup2(&fileActions, errorPipe[1], 2)
        if let workingDirectory {
            posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // A child inherits the spawning thread's signal mask, and GCD worker threads block signals some tools wait on.
        var emptySignals = sigset_t()
        sigemptyset(&emptySignals)
        posix_spawnattr_setsigmask(&attributes, &emptySignals)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK))

        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let spawnError = posix_spawn(&pid, executable, &fileActions, &attributes, argv, environ)
        close(outputPipe[1])
        close(errorPipe[1])
        let outputReader = FileHandle(fileDescriptor: outputPipe[0], closeOnDealloc: true)
        let errorReader = FileHandle(fileDescriptor: errorPipe[0], closeOnDealloc: true)
        guard spawnError == 0 else { return nil }

        var errorOutput = Data()
        let errorDrained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            errorOutput = errorReader.readDataToEndOfFile()
            errorDrained.signal()
        }
        let output = outputReader.readDataToEndOfFile()
        errorDrained.wait()

        var waitStatus: Int32 = 0
        while waitpid(pid, &waitStatus, 0) == -1 && errno == EINTR {}
        return ChildProcessResult(exitStatus: decodeExitStatus(waitStatus), output: output, errorOutput: errorOutput)
    }

    private static func decodeExitStatus(_ waitStatus: Int32) -> Int32 {
        let signal = waitStatus & 0x7f
        return signal == 0 ? (waitStatus >> 8) & 0xff : 128 + signal
    }
}
