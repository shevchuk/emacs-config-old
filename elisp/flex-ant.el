(require 'compile)
(defun build-flex (&optional target)
  "Call apache Ant via M-x comile and highlight errors."
  (interactive)
  (let* ((target (or target "main")) 
         (compilation-error-regexp-alist-alist 
          (list
           '(flex
             "^\\(.+\\)(\\([[:digit:]]+\\)): \\([^:]+: \\([[:digit:]]+\\)\\)?"
             1 2 4)))
         (compilation-error-regexp-alist
          (list
           'flex)))
    (compilation-start (concat "ant -emacs -s build.xml " target))))
(defun build-flex-target (target)
  (interactive "MAnt Target: ")
  (build-flex target))
(global-set-key [f11] 'build-flex)
(global-set-key [f10] 'build-flex-target)

(provide 'flex-ant)

