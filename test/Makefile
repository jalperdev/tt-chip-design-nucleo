# Makefile for MIPS-Lite Verilog-only simulation

SIM ?= icarus
SRC_DIR = $(CURDIR)/../src
PROJECT_SOURCES = project.v

ifeq ($(GATES),yes)
# Gate level simulation:
COMPILE_ARGS = -DGL_TEST -DFUNCTIONAL -DUSE_POWER_PINS -DSIM -DUNIT_DELAY=\#1 -I$(SRC_DIR)
VERILOG_SOURCES = $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/primitives.v \
                  $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/gf180mcu_fd_sc_mcu7t5v0.v \
                  $(CURDIR)/gate_level_netlist.v
else
# RTL simulation:
COMPILE_ARGS = -I$(SRC_DIR)
VERILOG_SOURCES = $(SRC_DIR)/$(PROJECT_SOURCES)
endif

all: test

test:
	iverilog -o sim_test -Wall -g2005 $(COMPILE_ARGS) $(VERILOG_SOURCES) tb.v
	vvp sim_test

clean:
	rm -f sim_test tb.vcd

.PHONY: all test clean
