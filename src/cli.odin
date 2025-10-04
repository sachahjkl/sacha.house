package main

import "core:fmt"
import "core:os"

handle_cli_args :: proc() {
	for arg in os.args[1:] {
		if arg == "-h" || arg == "--help" {
			print_help()
			os.exit(0)
		} else if arg == "-v" || arg == "--version" {
			print_version()
			os.exit(0)
		}
	}
}

@(private = "file")
print_version :: proc() {
	fmt.printf("%s+%s\n", VERSION_TAG, GIT_COMMIT_HASH)
}

@(private = "file")
print_help :: proc() {
	fmt.println("sacha.house - Personal website server")
	fmt.printf("Version: %s+%s\n\n", VERSION_TAG, GIT_COMMIT_HASH)
	
	fmt.println("USAGE:")
	fmt.println("  sacha.house [OPTIONS]")
	fmt.println()
	
	fmt.println("OPTIONS:")
	fmt.println("  -h, --help    Show this help message")
	fmt.println("  -v, --version Show version")
	fmt.println()
	
	fmt.println("ENVIRONMENT VARIABLES:")
	fmt.println("  CONFIG_PATH   Path to config file (default: config.json)")
	fmt.println("  PORT          Port to listen on (default: 6969)")
	fmt.println()
	
	fmt.println("EXAMPLES:")
	fmt.println("  sacha.house")
	fmt.println("  PORT=8080 sacha.house")
	fmt.println("  CONFIG_PATH=/etc/sacha.house/config.json PORT=8080 sacha.house")
}