;; ido 
(require 'ido)
(ido-mode t)
(setq ido-enable-flex-matching t
      ido-everywhere t
      ido-show-dot-for-dired t)

;; desktop
(require 'desktop)
(desktop-save-mode 1)
(add-to-list 'desktop-globals-to-save 'file-name-history)

;; as3 and actionscript modes
(autoload 'as3-mode "as3-mode" "as3-mode" t)
(autoload 'actionscript-mode "actionscript-mode" "actionscript-mode" t)

(setq auto-mode-alist (append '(("\\.as$" . as3-mode)) auto-mode-alist))
(add-to-list 'load-path "d:/emacs")

;; loading nxhtml
(load "D:/emacs/nxhtml/autostart.el")

(defun mumamo-chunk-mxml-script (pos min max)
  "Find ... , return range and actionscript-mode."
  (mumamo-quick-static-chunk pos min max "<fx:Script>" "</fx:Script>" nil 'actionscript-mode nil))

(define-mumamo-multi-major-mode mxml-actionscript-mumamo-mode
  "Turn on multiple major modes for MXML files with main mode `nxtml-mode'.This covers inlined Actionscript."
  ("MXML Actionscript Family" nxhtml-mode
   (mumamo-chunk-mxml-script
    )))

(add-to-list 'auto-mode-alist '("\\.mxml$" . mxml-actionscript-mumamo))

;; Mumamo is making emacs 23.3 freak out:
(when (and (equal emacs-major-version 23)
           (equal emacs-minor-version 3))
  (eval-after-load "bytecomp"
    '(add-to-list 'byte-compile-not-obsolete-vars
                  'font-lock-beginning-of-syntax-function))
  ;; tramp-compat.el clobbers this variable!
  (eval-after-load "tramp-compat"
    '(add-to-list 'byte-compile-not-obsolete-vars
                  'font-lock-beginning-of-syntax-function)))

;; as3-mode bindings
(global-set-key (kbd "C-c i") 'as3-indent-line)
(global-set-key (kbd "C-c C-d") 'as3-describe-class-by-name)

;; yasnippets
(require 'yasnippet)
(setq yas/root-directory "d:/emacs/snippets")
; Load the snippets
(yas/load-directory yas/root-directory)

;; git
(add-to-list 'load-path "d:/emacs/git-emacs")
(require 'git-emacs)

;; flex compilation
(require 'flex-ant)

;; MISC
;; rgrep from msys
(setenv "PATH"
  (concat
   ;; Change this with your path to MSYS bin directory
   "D:\\distr\\msysgit\\msysgit\\bin;"
   (getenv "PATH")))

;; show file name in window title
(setq frame-title-format
      (list (format "%s %%S: %%j " (system-name))
        '(buffer-file-name "%f" (dired-directory dired-directory "%b"))))

;; Prevent annoying bell
(setq visible-bell t)

;; F5 refreshes file
(defun refresh-file ()
  (interactive)
  (revert-buffer t t t)
  )

(global-set-key [f5] 'refresh-file)

(cd "d:/work/ePCN_2/flex/com/nxp/pcn/modules/avl/view/")