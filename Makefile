EMACS=emacs -Q --batch -nw
TARGETS=grammalecte.elc flycheck-grammalecte.elc

.PHONY: build clean cleanall demo

.INTERMEDIATE: dash.zip epl.zip flycheck.zip pkg-info.zip

all: build

build: $(TARGETS)

grammalecte.elc:
	$(EMACS) -f batch-byte-compile grammalecte.el

flycheck-grammalecte.elc: flycheck-master/flycheck.el
	$(EMACS) -L dash.el-master -L flycheck-master -L $(PWD) \
			 -f batch-byte-compile flycheck-grammalecte.el

clean:
	rm -rf Grammalecte-fr-v*
	rm -f debug "#example.org#"

cleanall: clean
	rm -rf grammalecte dash.el-master flycheck-master pkg-info-master epl-master
	rm -f $(TARGETS)

demo: grammalecte demo-no-grammalecte

demo-no-grammalecte: build
	touch debug
	emacs -Q --debug-init -l test-profile.el example.org

grammalecte:
	$(EMACS) -l grammalecte.el \
		--eval '(grammalecte-download-grammalecte "last")'

dash.zip:
	curl -Lso dash.zip https://github.com/magnars/dash.el/archive/master.zip

dash.el-master/dash.el: dash.zip
	unzip -qo dash.zip

epl.zip:
	curl -Lso epl.zip https://github.com/cask/epl/archive/master.zip

epl-master/epl.el: epl.zip
	unzip -qo epl.zip

pkg-info.zip:
	curl -Lso pkg-info.zip https://github.com/emacsorphanage/pkg-info/archive/master.zip

pkg-info-master/pkg-info.el: epl-master/epl.el pkg-info.zip
	unzip -qo pkg-info.zip
	touch pkg-info-master/pkg-info.el

flycheck.zip:
	curl -Lso flycheck.zip https://github.com/flycheck/flycheck/archive/master.zip

flycheck-master/flycheck.el: dash.el-master/dash.el pkg-info-master/pkg-info.el flycheck.zip
	unzip -qo flycheck.zip
	touch flycheck-master/flycheck.el
