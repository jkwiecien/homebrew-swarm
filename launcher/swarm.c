/*
 * SWARM.app's executable: run the command given in argv[1..] as a child process,
 * forward signals to it, and exit the way it exited.
 *
 * Why a child and not exec: macOS attributes privacy (TCC) prompts to the
 * *responsible* process, which for a LaunchAgent is the program launchd started.
 * If this program exec'd node, the process image would become node's and the
 * prompts would say "node" again. Staying alive as the parent keeps SWARM.app the
 * responsible process for the whole worker tree (node, git, claude, agy, codex).
 *
 * Contract (as SWARM's `~/.swarm/launchd-wrapper` expects it):
 *   - argv[1] is the program to run (absolute path or a name found on PATH),
 *     argv[2..] its arguments; the environment and working directory pass through.
 *   - SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGUSR1, SIGUSR2 are forwarded to the child.
 *   - Exit status is the child's; a child killed by a signal is mirrored by
 *     re-raising that signal here, so launchd sees the same termination.
 */

#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static volatile sig_atomic_t child_pid = 0;

static const int FORWARDED[] = {SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGUSR1, SIGUSR2};
#define FORWARDED_COUNT (sizeof(FORWARDED) / sizeof(FORWARDED[0]))

static void forward(int sig) {
	pid_t pid = (pid_t)child_pid;
	if (pid > 0) kill(pid, sig);
}

int main(int argc, char *argv[]) {
	if (argc < 2) {
		fprintf(stderr, "usage: %s <program> [args...]\n", argv[0]);
		return 64; /* EX_USAGE */
	}

	/* Block the forwarded signals until the child exists, so none is lost in between. */
	sigset_t forwarded, previous;
	sigemptyset(&forwarded);
	for (size_t i = 0; i < FORWARDED_COUNT; i++) sigaddset(&forwarded, FORWARDED[i]);
	sigprocmask(SIG_BLOCK, &forwarded, &previous);

	struct sigaction action;
	memset(&action, 0, sizeof(action));
	action.sa_handler = forward;
	sigemptyset(&action.sa_mask);
	action.sa_flags = SA_RESTART;
	for (size_t i = 0; i < FORWARDED_COUNT; i++) sigaction(FORWARDED[i], &action, NULL);

	/* The child starts with default dispositions and the mask this process inherited. */
	posix_spawnattr_t attr;
	posix_spawnattr_init(&attr);
	sigset_t defaults;
	sigemptyset(&defaults);
	for (size_t i = 0; i < FORWARDED_COUNT; i++) sigaddset(&defaults, FORWARDED[i]);
	posix_spawnattr_setsigdefault(&attr, &defaults);
	posix_spawnattr_setsigmask(&attr, &previous);
	posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);

	pid_t pid;
	int err = posix_spawnp(&pid, argv[1], NULL, &attr, &argv[1], environ);
	posix_spawnattr_destroy(&attr);
	if (err != 0) {
		fprintf(stderr, "swarm: cannot start %s: %s\n", argv[1], strerror(err));
		return 127;
	}
	child_pid = pid;
	sigprocmask(SIG_SETMASK, &previous, NULL);

	int status;
	for (;;) {
		pid_t done = waitpid(pid, &status, 0);
		if (done == pid) break;
		if (done == -1 && errno == EINTR) continue;
		perror("swarm: waitpid");
		return 70; /* EX_SOFTWARE */
	}

	if (WIFEXITED(status)) return WEXITSTATUS(status);
	if (WIFSIGNALED(status)) {
		int sig = WTERMSIG(status);
		signal(sig, SIG_DFL);
		sigset_t only;
		sigemptyset(&only);
		sigaddset(&only, sig);
		sigprocmask(SIG_UNBLOCK, &only, NULL);
		raise(sig);
		return 128 + sig; /* reached only for a signal that does not terminate */
	}
	return 70;
}
