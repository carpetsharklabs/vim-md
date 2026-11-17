VIM ?= vim
NVIM ?= nvim

.PHONY: test
test:
	@out=$$(mktemp); rc=0; \
	VIM_MD_TEST_OUT=$$out $(VIM) -u NONE -N -es --cmd 'set enc=utf-8' -S tests/run.vim || rc=1; \
	echo "vim:    $$(tail -1 $$out)"; \
	if command -v $(NVIM) >/dev/null 2>&1; then \
	  VIM_MD_TEST_OUT=$$out $(NVIM) -u NONE -es -S tests/run.vim || rc=1; \
	  echo "neovim: $$(tail -1 $$out)"; \
	fi; \
	exit $$rc
