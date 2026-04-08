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
         (project-root (scope-toggler--project-root))
         (default-directory project-root)
         (find-fn (plist-get scope :find-buffer))
         (buf (if find-fn
                  (funcall find-fn project-root)
                (get-buffer (scope-toggler--buffer-name scope-name project-root))))
         (win (and buf (get-buffer-window buf t)))
         (height (or (plist-get scope :window-height)
                     scope-toggler-default-window-height))
         (display-action `(display-buffer-in-side-window
                           (side . bottom) (window-height . ,height))))
    (unless scope
      (user-error "Unknown scope: %s" scope-name))
    (cond
     ;; Visible -> hide
     ((and win (window-live-p win))
      (when (eq (selected-window) win)
        (when (and scope-toggler--previous-window
                   (window-live-p scope-toggler--previous-window))
          (select-window scope-toggler--previous-window)))
      (delete-window win))
     ;; Exists but hidden -> show
     (buf
      (setq scope-toggler--previous-window (selected-window))
      (let ((w (display-buffer buf display-action)))
        (when w (select-window w))))
     ;; No buffer -> create and show
     (t
      (setq scope-toggler--previous-window (selected-window))
      (let ((new-buf (funcall (plist-get scope :create) project-root)))
        (when (and new-buf (buffer-live-p new-buf))
          (let ((w (display-buffer new-buf display-action)))
            (when w (select-window w)))))))))

;;;###autoload
(defmacro scope-toggler-make-command (command-name scope-name)
  "Define interactive command COMMAND-NAME that toggles SCOPE-NAME."
  `(defun ,command-name ()
     ,(format "Toggle `%s' scope for the current project." scope-name)
     (interactive)
     (scope-toggler-toggle ,scope-name)))

(provide 'scope-toggler)
;;; scope-toggler.el ends here
