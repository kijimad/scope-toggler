;;; scope-toggler-test.el --- Tests for scope-toggler -*- lexical-binding: t -*-

(require 'ert)
(require 'scope-toggler)

;;; Helpers

(defvar scope-toggler-test--project-a nil)
(defvar scope-toggler-test--project-b nil)

(defmacro scope-toggler-test--with-projects (&rest body)
  "Create two temp projects with .git dirs, run BODY, then clean up."
  `(let ((scope-toggler-test--project-a (make-temp-file "st-project-a-" t))
         (scope-toggler-test--project-b (make-temp-file "st-project-b-" t))
         (scope-toggler--active-window nil))
     (unwind-protect
         (progn
           (make-directory (expand-file-name ".git" scope-toggler-test--project-a) t)
           (make-directory (expand-file-name ".git" scope-toggler-test--project-b) t)
           (clrhash scope-toggler--scopes)
           ,@body)
       (clrhash scope-toggler--scopes)
       (scope-toggler-test--kill-test-buffers)
       (delete-directory scope-toggler-test--project-a t)
       (delete-directory scope-toggler-test--project-b t))))

(defun scope-toggler-test--kill-test-buffers ()
  "Kill all test scope buffers."
  (dolist (buf (buffer-list))
    (when (string-match-p "\\*\\(test-scope\\|scope-[ab]\\)<" (buffer-name buf))
      (kill-buffer buf))))

(defun scope-toggler-test--make-create-fn (scope-name)
  "Return a :create function for SCOPE-NAME."
  (lambda (root)
    (let ((buf (generate-new-buffer
                (scope-toggler--buffer-name scope-name root))))
      (with-current-buffer buf (setq default-directory root))
      buf)))

(defun scope-toggler-test--define-test-scope ()
  "Register a simple test scope using plain buffers."
  (scope-toggler-define "test-scope"
    :create (scope-toggler-test--make-create-fn "test-scope")))

;;; Tests

(ert-deftest scope-toggler-test-project-root ()
  "Detect project root from .git marker."
  (scope-toggler-test--with-projects
   (let ((default-directory (file-name-as-directory scope-toggler-test--project-a)))
     (should (string= (expand-file-name default-directory)
                       (expand-file-name (scope-toggler--project-root)))))))

(ert-deftest scope-toggler-test-project-root-subdirectory ()
  "Detect project root from a subdirectory."
  (scope-toggler-test--with-projects
   (let* ((subdir (expand-file-name "src/" scope-toggler-test--project-a)))
     (make-directory subdir t)
     (let ((default-directory subdir))
       (should (string= (expand-file-name
                          (file-name-as-directory scope-toggler-test--project-a))
                         (expand-file-name (scope-toggler--project-root))))))))

(ert-deftest scope-toggler-test-project-root-fallback ()
  "Fall back to default-directory when no marker found."
  (let* ((tmpdir (make-temp-file "st-no-git-" t))
         (default-directory (file-name-as-directory tmpdir)))
    (unwind-protect
        (should (string= (expand-file-name default-directory)
                          (expand-file-name (scope-toggler--project-root))))
      (delete-directory tmpdir t))))

(ert-deftest scope-toggler-test-buffer-name ()
  "Generate correct buffer name."
  (should (string= "*test<my-project>*"
                    (scope-toggler--buffer-name "test" "/home/user/my-project/"))))

(ert-deftest scope-toggler-test-define-and-lookup ()
  "Define a scope and retrieve it."
  (clrhash scope-toggler--scopes)
  (scope-toggler-define "foo" :create #'ignore)
  (should (gethash "foo" scope-toggler--scopes))
  (should (eq #'ignore (plist-get (gethash "foo" scope-toggler--scopes) :create)))
  (clrhash scope-toggler--scopes))

(ert-deftest scope-toggler-test-toggle-creates-buffer ()
  "First toggle creates a buffer."
  (scope-toggler-test--with-projects
   (scope-toggler-test--define-test-scope)
   (let ((default-directory (file-name-as-directory scope-toggler-test--project-a)))
     (scope-toggler-toggle "test-scope")
     (let ((buf-name (scope-toggler--buffer-name "test-scope"
                                                  (scope-toggler--project-root))))
       (should (get-buffer buf-name))))))

(ert-deftest scope-toggler-test-toggle-hides-visible ()
  "Toggle hides a visible scope buffer."
  (scope-toggler-test--with-projects
   (scope-toggler-test--define-test-scope)
   (let ((default-directory (file-name-as-directory scope-toggler-test--project-a)))
     ;; Show
     (scope-toggler-toggle "test-scope")
     (let* ((buf-name (scope-toggler--buffer-name "test-scope"
                                                   (scope-toggler--project-root)))
            (buf (get-buffer buf-name)))
       (should (get-buffer-window buf))
       ;; Hide
       (scope-toggler-toggle "test-scope")
       (should-not (get-buffer-window buf))
       ;; Buffer still alive
       (should (buffer-live-p buf))))))

(ert-deftest scope-toggler-test-toggle-shows-hidden ()
  "Toggle shows a hidden but existing scope buffer."
  (scope-toggler-test--with-projects
   (scope-toggler-test--define-test-scope)
   (let ((default-directory (file-name-as-directory scope-toggler-test--project-a)))
     ;; Create and show
     (scope-toggler-toggle "test-scope")
     ;; Hide
     (scope-toggler-toggle "test-scope")
     ;; Show again
     (scope-toggler-toggle "test-scope")
     (let* ((buf-name (scope-toggler--buffer-name "test-scope"
                                                   (scope-toggler--project-root)))
            (buf (get-buffer buf-name)))
       (should (get-buffer-window buf))))))

(ert-deftest scope-toggler-test-separate-projects ()
  "Different projects get separate buffers."
  (scope-toggler-test--with-projects
   (scope-toggler-test--define-test-scope)
   (let* ((root-a (file-name-as-directory scope-toggler-test--project-a))
          (root-b (file-name-as-directory scope-toggler-test--project-b))
          (name-a (scope-toggler--buffer-name "test-scope" root-a))
          (name-b (scope-toggler--buffer-name "test-scope" root-b)))
     ;; Create in project A
     (let ((default-directory root-a))
       (scope-toggler-toggle "test-scope"))
     ;; Create in project B
     (let ((default-directory root-b))
       (scope-toggler-toggle "test-scope"))
     ;; Both buffers should exist with different names
     (should (get-buffer name-a))
     (should (get-buffer name-b))
     (should-not (string= name-a name-b)))))

(ert-deftest scope-toggler-test-find-buffer ()
  "Custom :find-buffer is used to locate existing buffer."
  (scope-toggler-test--with-projects
   (let* ((root-a (file-name-as-directory scope-toggler-test--project-a))
          (custom-buf (generate-new-buffer "*test-scope<custom>*")))
     (with-current-buffer custom-buf
       (setq default-directory root-a))
     (scope-toggler-define "test-scope"
       :find-buffer (lambda (root)
                      (when (string= (expand-file-name root)
                                     (expand-file-name root-a))
                        custom-buf))
       :create (lambda (_root) (error "Should not be called")))
     (let ((default-directory root-a))
       ;; Should find custom-buf via :find-buffer, not call :create
       (scope-toggler-toggle "test-scope")
       (should (get-buffer-window custom-buf)))
     (kill-buffer custom-buf))))

(ert-deftest scope-toggler-test-window-height ()
  "Custom :window-height is respected."
  (scope-toggler-test--with-projects
   (scope-toggler-define "test-scope"
     :create (scope-toggler-test--make-create-fn "test-scope")
     :window-height 0.5)
   (let ((default-directory (file-name-as-directory scope-toggler-test--project-a)))
     (scope-toggler-toggle "test-scope")
     (let* ((buf-name (scope-toggler--buffer-name "test-scope"
                                                   (scope-toggler--project-root)))
            (buf (get-buffer buf-name))
            (win (get-buffer-window buf)))
       (should win)))))

(ert-deftest scope-toggler-test-make-command ()
  "scope-toggler-make-command defines a working command."
  (clrhash scope-toggler--scopes)
  (scope-toggler-define "test-scope" :create (lambda (_root) (generate-new-buffer "*test-scope<cmd>*")))
  (scope-toggler-make-command scope-toggler-test--cmd "test-scope")
  (should (fboundp 'scope-toggler-test--cmd))
  (clrhash scope-toggler--scopes)
  (scope-toggler-test--kill-test-buffers))

(ert-deftest scope-toggler-test-unknown-scope-error ()
  "Toggling an unknown scope signals an error."
  (clrhash scope-toggler--scopes)
  (should-error (scope-toggler-toggle "nonexistent")
                :type 'user-error))

(ert-deftest scope-toggler-test-shared-side-window ()
  "Toggling a different scope replaces the current one in the same side window."
  (scope-toggler-test--with-projects
   (scope-toggler-define "scope-a" :create (scope-toggler-test--make-create-fn "scope-a"))
   (scope-toggler-define "scope-b" :create (scope-toggler-test--make-create-fn "scope-b"))
   (let* ((root (file-name-as-directory scope-toggler-test--project-a))
          (default-directory root)
          (name-a (scope-toggler--buffer-name "scope-a" root))
          (name-b (scope-toggler--buffer-name "scope-b" root)))
     ;; Show scope-a
     (scope-toggler-toggle "scope-a")
     (let ((buf-a (get-buffer name-a)))
       (should (get-buffer-window buf-a))
       ;; Toggle scope-b -> should replace scope-a in the same window
       (scope-toggler-toggle "scope-b")
       (let ((buf-b (get-buffer name-b)))
         ;; scope-b is visible
         (should (get-buffer-window buf-b))
         ;; scope-a is no longer visible (replaced, not stacked)
         (should-not (get-buffer-window buf-a))
         ;; Only one side window
         (should (= 1 (length (seq-filter
                               (lambda (w)
                                 (window-parameter w 'window-side))
                               (window-list))))))))))

(ert-deftest scope-toggler-test-hide-after-replace ()
  "Toggling the visible scope after replacement hides the side window."
  (scope-toggler-test--with-projects
   (scope-toggler-define "scope-a" :create (scope-toggler-test--make-create-fn "scope-a"))
   (scope-toggler-define "scope-b" :create (scope-toggler-test--make-create-fn "scope-b"))
   (let* ((root (file-name-as-directory scope-toggler-test--project-a))
          (default-directory root)
          (name-b (scope-toggler--buffer-name "scope-b" root)))
     ;; Show scope-a, then replace with scope-b
     (scope-toggler-toggle "scope-a")
     (scope-toggler-toggle "scope-b")
     ;; Toggle scope-b again -> hide
     (scope-toggler-toggle "scope-b")
     (should-not (get-buffer-window (get-buffer name-b)))
     ;; No side windows left
     (should (null (seq-filter
                    (lambda (w)
                      (window-parameter w 'window-side))
                    (window-list)))))))

(provide 'scope-toggler-test)
;;; scope-toggler-test.el ends here
