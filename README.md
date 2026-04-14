# scope-toggler

Toggle project-scoped buffers in Emacs using side windows.

Like [vterm-toggle](https://github.com/jixiuf/vterm-toggle), but generalized — register any buffer type and get one-per-project toggling with a single keypress. Existing window splits are never disrupted.

## How it works

1. Define a **scope** — a named buffer type with a `:create` function
2. Toggle it — scope-toggler finds the project root (via `.git`), then:
   - **Buffer visible** → hide (delete side window, restore focus)
   - **Buffer exists but hidden** → show in side window
   - **No buffer** → create and show

## Install

```elisp
(use-package scope-toggler
  :straight (:host github :repo "kijimad/scope-toggler"))
```

## Usage

### eshell

```elisp
(scope-toggler-define "eshell"
  :create (lambda (root)
            (let ((default-directory root))
              (with-current-buffer (eshell 'N)
                (rename-buffer (format "*eshell<%s>*"
                                       (file-name-nondirectory
                                        (directory-file-name root))))
                (current-buffer)))))

(scope-toggler-make-command my/toggle-eshell "eshell")
(global-set-key (kbd "C-M-;") #'my/toggle-eshell)
```

### vterm

```elisp
(scope-toggler-define "vterm"
  :create (lambda (root)
            (let ((default-directory root))
              (vterm (format "*vterm<%s>*"
                             (file-name-nondirectory
                              (directory-file-name root)))))))

(scope-toggler-make-command my/toggle-vterm "vterm")
(global-set-key (kbd "C-M-:") #'my/toggle-vterm)
```

### agent-shell

```elisp
  (scope-toggler-define "agent-shell"
   :find-buffer (lambda (root)
                 (seq-first
                  (seq-filter
                   (lambda (buf)
                    (string= (expand-file-name root)
                     (expand-file-name
                      (buffer-local-value 'default-directory buf))))
                         (agent-shell-buffers))))
        :create (lambda (root)
                  (let* ((default-directory root)
                         (buf (agent-shell--start
                               :config (or (agent-shell--resolve-preferred-config)
                                           (agent-shell-select-config
                                            :prompt "Start new agent: ")
                                           (error "No agent config found")))))
                    (when current-prefix-arg
                      (with-current-buffer buf
                        (setq-local agent-shell-permission-responder-function
                    #'agent-shell-permission-allow-always)))
                    buf)))

(scope-toggler-make-command my/toggle-agent-shell "agent-shell")
(global-set-key (kbd "C-M-@") #'my/toggle-agent-shell)
```

## API

### `scope-toggler-define` (name &rest props)

Register a scope. Props:

| Key | Description |
|-----|-------------|
| `:create` | **(required)** `(lambda (project-root) ...)` — create and return a buffer |
| `:find-buffer` | `(lambda (project-root) ...)` — find existing buffer, return it or nil. Falls back to name-based matching if omitted |
| `:window-height` | Side window height (0.0–1.0). Default: `0.35` |

### `scope-toggler-toggle` (scope-name)

Toggle the scope buffer for the current project. Works as an interactive command with completion.

### `scope-toggler-make-command` (command-name scope-name)

Macro. Define an interactive command that toggles the given scope.

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `scope-toggler-project-markers` | `'(".git")` | Files/dirs that identify a project root |
| `scope-toggler-default-window-height` | `0.35` | Default side window height |

## License

GPL-3.0
