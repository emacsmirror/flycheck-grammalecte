EMACS=emacs -Q --batch -nw
TARGETS=grammalecte.elc flycheck-grammalecte.elc

.PHONY: autoloads build clean cleanall

all: build

build: $(TARGETS)

autoloads: grammalecte-loaddefs.el

define LOADDEFS_TPL
(add-to-list 'load-path (directory-file-name\n\
........................(or (file-name-directory #$$) (car load-path))))
endef
#' (ends emacs font-face garbage due to previous single quote)

grammalecte-loaddefs.el:
	rm -f $@
	$(EMACS) -L $(PWD) \
		--eval "(setq-default backup-inhibited t)" \
		--eval "(setq generated-autoload-file \"$(PWD)/$@\")" \
		--eval "(update-directory-autoloads \"$(PWD)\")"
	sed -i "s/^;;; Code:$$/;;; Code:\n\n$(subst ., ,$(LOADDEFS_TPL))/" $@

grammalecte.elc:
	$(EMACS) -f batch-byte-compile grammalecte.el

flycheck-grammalecte.elc: dash.el-master flycheck-master
	$(EMACS) -L dash.el-master -L flycheck-master -L $(PWD) \
			 -f batch-byte-compile flycheck-grammalecte.el

clean:
	rm -f *.zip
	rm -rf Grammalecte-fr-v*

cleanall: clean cleandemo
	rm -rf grammalecte *-master
	rm -f $(TARGETS) grammalecte-loaddefs.el

grammalecte:
	$(EMACS) --eval "(setq grammalecte-settings-file \"/dev/null\")" \
			-l grammalecte.el -f grammalecte-download-grammalecte

######### Demo related targets

.PHONY: demo demo-deps demo-no-grammalecte demo-use-package

EMACS_DEMO = HOME=$(PWD)/test-home emacs --debug-init

demo: demo-deps grammalecte
	$(EMACS_DEMO) -l test-home/classic.el example.org

demo-no-grammalecte: demo-deps
	$(EMACS_DEMO) -l test-home/classic.el example.org

demo-use-package: demo-deps use-package-master
	$(EMACS_DEMO) -l test-home/use-package.el example.org

demo-deps: cleandemo build autoloads epl-master pkg-info-master
	touch debug

cleandemo:
	rm -rf grammalecte
	rm -f debug "#example.org#"
	rm -f test-home/grammalecte-cache.el

######### Dependencies

use-package_author = jwiegley
epl_author = cask
pkg-info_author = emacsorphanage
dash.el_author = magnars
flycheck_author = flycheck

%.zip:
	curl -Lso $@ https://github.com/$($(@:%.zip=%)_author)/$(@:%.zip=%)/archive/master.zip

%-master: %.zip
	unzip -qo $<
