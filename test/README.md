# How to Test
You need to have verilator installed

``` sh
python3 -m venv ./hdltestenv
source ./hdltestenv/bin/activate
pip3 install -r ./requirements.txt
pytest -s -o log_cli=True
# or
pytest -s -o log_cli=True -s test_my_module.py
```

