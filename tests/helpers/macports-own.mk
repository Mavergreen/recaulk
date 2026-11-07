# Included after MacPorts' own Makefile (make -f Makefile -f this): build its static test programs
# without running them, so they can run on a 10.9 guest, and list them for that run.
recaulk_static_progs: $(TESTSPRGS)

recaulk_list_static:
	@printf '%s\n' $(TESTSPRGS)

.PHONY: recaulk_static_progs recaulk_list_static
