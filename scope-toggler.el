;;; scope-toggler.el --- Toggle project-scoped buffers -*- lexical-binding: t -*-

;; Author: violet
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: convenience, terminals, processes

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Toggle project-scoped buffers using side windows.
;;
;;   (scope-toggler-define "agent-shell"
;;     :find-buffer (lambda (_root) (seq-first (agent-shell-project-buffers)))
;;     :create (lambda (root)
;;               (let ((default-directory root)
;;                     (agent-shell-context-sources nil))
;;                 (agent-shell)
;;                 (seq-first (agent-shell-project-buffers)))))
;;
;;   (scope-toggler-make-command my/toggle-agent-shell "agent-shell")
;;   (global-set-key (kbd "<muhenkan>") #'my/toggle-agent-shell)

;;; Code:

(defgroup scope-toggler nil
  "Toggle project-scoped buffers."
  :group 'convenience
  :prefix "scope-toggler-")

(defcustom scope-toggler-project-markers '(".git")
  "File/directory names that identify a project root."
  :type '(repeat string)
  :group 'scope-toggler)

(defcustom scope-toggler-default-window-height 0.35
  "Default height for side windows."
  :type 'number
  :group 'scope-toggler)

(defvar scope-toggler--scopes (make-hash-table :test 'equal))
(defvar scope-toggler--previous-window nil)
(defvar scope-toggler--active-window nil
  "The current side window used by scope-toggler, shared across all scopes.")

(defun scope-toggler--project-root ()
  "Find project root by searching upward for `scope-toggler-project-markers'."
  (let ((dir default-directory) root)
    (dolist (marker scope-toggler-project-markers)
      (let ((found (locate-dominating-file dir marker)))
        (when (and found (or (null root) (> (length found) (length root))))
          (setq root found))))
    (or root default-directory)))

(defun scope-toggler--buffer-name (scope-name project-root)
  "Generate buffer name for SCOPE-NAME in PROJECT-ROOT."
  (format "*%s<%s>*"
          scope-name
          (file-name-nondirectory (directory-file-name project-root))))

(defun scope-toggler--create (create-fn project-root)
  "Call CREATE-FN with PROJECT-ROOT, restoring current window's buffer if hijacked."
  (let ((orig-win (selected-window))
        (orig-buf (current-buffer)))
    (let ((new-buf (funcall create-fn project-root)))
      (when (and new-buf
                 (window-live-p orig-win)
                 (not (eq orig-buf new-buf))
                 (eq (window-buffer orig-win) new-buf))
        (set-window-buffer orig-win orig-buf))
      new-buf)))

(defun scope-toggler--show (buf display-action)
  "Show BUF in a side window using DISPLAY-ACTION, track state, and select it."
  (unless (eq (selected-window) scope-toggler--active-window)
    (setq scope-toggler--previous-window (selected-window)))
  (let ((w (display-buffer buf display-action)))
    (when w
      (setq scope-toggler--active-window w)
      (select-window w))))

;;;###autoload
(defun scope-toggler-define (name &rest props)
  "Register scope NAME with PROPS.

  :create       (REQUIRED) Function (PROJECT-ROOT) -> buffer.
  :find-buffer  Function (PROJECT-ROOT) -> buffer or nil.
  :window-height  Height for side window."
  (puthash name props scope-toggler--scopes))

;;;###autoload
(defun scope-toggler-toggle (scope-name)
  "Toggle the buffer for SCOPE-NAME in the current project."
  (interactive
   (list (completing-read "Scope: "
                          (hash-table-keys scope-toggler--scopes) nil t)))
  (let* ((scope (gethash scope-name scope-toggler--scopes))
         (_ (unless scope (user-error "Unknown scope: %s" scope-name)))
         (project-root (scope-toggler--project-root))
         (default-directory project-root)
         (find-fn (plist-get scope :find-buffer))
         (create-fn (plist-get scope :create))
         (buf (if find-fn
                  (funcall find-fn project-root)
                (get-buffer (scope-toggler--buffer-name scope-name project-root))))
         (win (and buf (get-buffer-window buf)))
         (height (or (plist-get scope :window-height)
                     scope-toggler-default-window-height))
         (display-action `(display-buffer-in-side-window
                           (side . bottom) (window-height . ,height))))
    (cond
     ;; Visible -> hide
     ((and win (window-live-p win))
      (when (eq (selected-window) win)
        (when (and scope-toggler--previous-window
                   (window-live-p scope-toggler--previous-window))
          (select-window scope-toggler--previous-window)))
      (delete-window win)
      (setq scope-toggler--active-window nil))
     ;; Not visible -> get or create buffer, show in side window
     (t
      (let ((target (or buf (scope-toggler--create create-fn project-root))))
        (when (and target (buffer-live-p target))
          (scope-toggler--show target display-action)))))))

;;;###autoload
(defmacro scope-toggler-make-command (command-name scope-name)
  "Define interactive command COMMAND-NAME that toggles SCOPE-NAME."
  `(defun ,command-name ()
     ,(format "Toggle `%s' scope for the current project." scope-name)
     (interactive)
     (scope-toggler-toggle ,scope-name)))

(provide 'scope-toggler)
;;; scope-toggler.el ends here
