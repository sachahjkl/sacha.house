package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/term"

	"sacha.house/internal/app"
	"sacha.house/internal/auth"
)

var (
	version    = "dev"
	commitHash = "dev"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

func run(arguments []string) error {
	development := false
	for index := 0; index < len(arguments); index++ {
		argument := arguments[index]
		switch {
		case argument == "-h" || argument == "--help":
			printHelp()
			return nil
		case argument == "-v" || argument == "--version":
			fmt.Println(version)
			return nil
		case argument == "-dev":
			development = true
		case argument == "--hash-password":
			password, err := readPassword()
			if err != nil {
				return err
			}
			config, err := app.LoadConfig(app.ConfigPath())
			if err != nil {
				return err
			}
			if config.PasswordPepper() == "" {
				return errors.New("ADMIN_PASSWORD_PEPPER must be set in config")
			}
			hash, err := auth.HashPassword(password, []byte(config.PasswordPepper()))
			if err != nil {
				return err
			}
			fmt.Println(hash)
			return nil
		default:
			return fmt.Errorf("unknown argument %q", argument)
		}
	}

	config, err := app.LoadConfig(app.ConfigPath())
	if err != nil {
		return err
	}
	application, err := app.NewWithOptions(config, app.Options{
		Version: version, CommitHash: commitHash, Development: development,
	})
	if err != nil {
		return err
	}

	address := net.JoinHostPort(app.Host(), strconv.Itoa(app.Port()))
	server := &http.Server{
		Addr:              address,
		Handler:           application,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	stopped := make(chan os.Signal, 1)
	signal.Notify(stopped, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(stopped)

	serverError := make(chan error, 1)
	go func() { serverError <- server.ListenAndServe() }()
	fmt.Printf("Listening on http://%s\n", address)

	select {
	case err := <-serverError:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	case <-stopped:
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return server.Shutdown(ctx)
	}
}

func readPassword() (string, error) {
	if term.IsTerminal(int(os.Stdin.Fd())) {
		fmt.Fprint(os.Stderr, "Password: ")
		value, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		if err != nil {
			return "", fmt.Errorf("read password: %w", err)
		}
		if len(value) == 0 {
			return "", errors.New("password is empty")
		}
		return string(value), nil
	}
	value, err := io.ReadAll(io.LimitReader(os.Stdin, 4097))
	if err != nil {
		return "", fmt.Errorf("read password: %w", err)
	}
	password := strings.TrimSpace(string(value))
	if password == "" || len(password) > 4096 {
		return "", errors.New("password input is empty or too large")
	}
	return password, nil
}

func printHelp() {
	fmt.Printf(`sacha.house - Personal website server
Version: %s

USAGE:
  sacha.house [OPTIONS]

OPTIONS:
  -h, --help              Show this help message
  -v, --version           Show version
  -dev                    Run in development mode
  --hash-password         Read a password securely and generate its Argon2id hash

ENVIRONMENT VARIABLES:
  CONFIG_PATH   Path to config file (default: config.json)
  HOST          Host address to bind (default: 127.0.0.1)
  PORT          Port to listen on (default: 6969)
`, version)
}
