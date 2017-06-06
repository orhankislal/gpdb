RELENG_TOOLS=$(RELENGTOOLS)

include $(BLD_TOP)/Makefile.global

# e.g.
# $(RELENG_TOOLS)/geos-3.2.2
# $(RELENG_TOOLS)/proj-4.7.0
TOOL_ARGS=$(subst -, ,$*)
TOOL_NAME=$(word 1,$(TOOL_ARGS))
TOOL_VER=$(word 2,$(TOOL_ARGS))
$(RELENG_TOOLS)/%:
