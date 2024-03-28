import re
from enum import Enum
from sys import argv


class ParseLintTXT:
    p_table = re.compile('^\\+(-+\\+)+$')

    class ParseState(Enum):
        IDLE = 0
        HEADER1 = 1
        HEADER2 = 1
        DATA = 2
    state = ParseState.IDLE
    curr_table = []
    curr_col_len = []
    tables = []

    def __init__(self, filename):
        self.parse_file(filename)

    def parse_with_col_len(self, line):
        out = []
        col_len = self.curr_col_len.copy()

        while True:
            if len(line) == 0 or line[0] != '|':
                return None

            line = line[1:]

            if len(col_len) == 0:
                break

            out.append(line[:col_len[0]].strip())
            line = line[col_len[0]:]
            col_len = col_len[1:]

        if len(line) != 0:
            return None

        return out

    def on_horizontal_separation(self, line):
        col_len = [len(i) for i in line.split('+')[1:-1]]

        if self.state == self.ParseState.IDLE:
            self.curr_col_len = col_len
            self.curr_table = {'header': None, 'lines': [], 'ascii': [line]}
            self.state = self.ParseState.HEADER1
        elif self.state == self.ParseState.HEADER2:
            if self.curr_col_len != col_len:
                self.state = self.ParseState.IDLE
            else:
                self.curr_table['ascii'].append(line)
                self.state = self.ParseState.DATA
        elif self.state == self.ParseState.DATA:
            if self.curr_col_len != col_len:
                self.state = self.ParseState.IDLE
            else:
                self.curr_table['ascii'].append(line)
                self.tables.append(self.curr_table)
                self.state = self.ParseState.IDLE
        else:
            self.state = self.ParseState.IDLE

    def on_data(self, line, data):
        if self.state == self.ParseState.HEADER1:
            self.curr_table['header'] = data
            self.curr_table['ascii'].append(line)
            self.state = self.ParseState.HEADER2
        elif self.state == self.ParseState.DATA:
            self.curr_table['lines'].append(data)
            self.curr_table['ascii'].append(line)
        else:
            self.state = self.ParseState.IDLE

    def on_unknown(self, line):
        if self.state == self.ParseState.DATA and len(self.curr_table['lines']) == 0:
            self.tables.append(self.curr_table)
            self.state = self.ParseState.IDLE
        else:
            self.state = self.ParseState.IDLE

    def parse_file(self, filename):
        with open(filename, 'r', encoding='ASCII') as f:
            for line in f:
                line = line.strip()

                # Check for "+-----+-----+"
                if self.p_table.match(line):
                    self.on_horizontal_separation(line)
                    continue

                # Check for "| abc | 123 |"
                data = self.parse_with_col_len(line)

                if data is None:
                    self.on_unknown(line)
                else:
                    self.on_data(line, data)

    def validate(self):
        # There are two tables: Summary and Expanded
        assert len(self.tables) == 2

        # In case of errors, print the expanded table
        print('\n'.join(self.tables[1]['ascii']))

        # The fields "# Violations" and "# Waived" must match for all groups
        assert self.tables[0]['header'][1] == '# Violations'
        assert self.tables[0]['header'][2] == '# Waived'
        assert all([line[1] == line[2] for line in self.tables[0]['lines']])

        # The expanded table must be empty
        assert len(self.tables[1]['lines']) == 0


if __name__ == '__main__':
    lint = ParseLintTXT(argv[1])
    lint.validate()
