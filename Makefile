
# ---------- DYNAMICALLY GENERATED SOURCE FILES ----------

# Meta-target for generated-sources, usable for test benches etc.
gen_srcs: gen_srcs/eth_crc_128b_comb.v

gen_srcs/pyenv/bin/activate:
	mkdir -p gen_srcs/
	python3 -m venv gen_srcs/pyenv/

gen_srcs/eth_crc_128b_comb.v: gen_srcs/pyenv/bin/activate scripts/crc.py
	bash -c " \
	  source gen_srcs/pyenv/bin/activate; \
	  pip3 install -r scripts/crc_requirements.txt; \
	  python3 scripts/crc.py \
	    --round-bits 128 \
	    --verilog-mod-name eth_crc_128b_comb \
	    gen-verilog > gen_srcs/eth_crc_128b_comb.v \
	"
