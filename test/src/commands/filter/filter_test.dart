import 'package:args/command_runner.dart';
import 'package:coverde/src/commands/filter/filter.dart';
import 'package:coverde/src/entities/tracefile.dart';
import 'package:coverde/src/utils/path.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import '../../../utils/mocks.dart';

extension _FixturedString on String {
  String get fixturePath => path.join(
        'test/src/commands/filter/fixtures/',
        this,
      );
}

void main() {
  group(
    '''

GIVEN a tracefile filterer command''',
    () {
      late CommandRunner<void> cmdRunner;
      late MockStdout out;
      late FilterCommand filterCmd;

      // ARRANGE
      setUp(
        () {
          cmdRunner = CommandRunner<void>('test', 'A tester command runner');
          out = MockStdout();
          filterCmd = FilterCommand(out: out);
          cmdRunner.addCommand(filterCmd);
        },
      );

      tearDown(
        () {
          verifyNoMoreInteractions(out);
        },
      );

      test(
        '''

WHEN its description is requested
THEN a proper abstract should be returned
''',
        () {
          // ARRANGE
          const expected = '''
Filter a coverage trace file.

Filter the coverage info by ignoring data related to files with paths that matches the given FILTERS.
The coverage data is taken from the INPUT_LCOV_FILE file and the result is appended to the OUTPUT_LCOV_FILE file.
''';

          // ACT
          final result = filterCmd.description;

          // ASSERT
          expect(result.trim(), expected.trim());
        },
      );

      test(
        '''

AND an existing tracefile to filter
AND a set of patterns to be filtered
WHEN the command is invoqued
THEN a filtered tracefile should be created
├─ BY dumping the filtered content to the default destination
''',
        () async {
          // ARRANGE
          const patterns = <String>['.g.dart'];
          final patternsRegex = patterns.map((_) => RegExp(_));
          final originalFilePath = 'original.lcov.info'.fixturePath;
          final filteredFilePath = 'filtered.lcov.info'.fixturePath;
          final originalFile = File(originalFilePath);
          final filteredFile = File(filteredFilePath);
          if (filteredFile.existsSync()) {
            filteredFile.deleteSync(recursive: true);
          }
          final originalTracefile = Tracefile.parse(
            originalFile.readAsStringSync(),
          );
          final originalFileIncludeFileThatMatchPatterns =
              originalTracefile.includeFileThatMatchPatterns(patterns);
          final filesDataToBeRemoved =
              originalTracefile.sourceFilesCovData.where(
            (d) => patternsRegex.any(
              (r) => r.hasMatch(d.source.path),
            ),
          );

          expect(originalFile.existsSync(), isTrue);
          expect(filteredFile.existsSync(), isFalse);
          expect(originalFileIncludeFileThatMatchPatterns, isTrue);

          // ACT
          await cmdRunner.run([
            filterCmd.name,
            '--${FilterCommand.inputOption}',
            originalFilePath,
            '--${FilterCommand.outputOption}',
            filteredFilePath,
            '--${FilterCommand.filtersOption}',
            patterns.join(','),
          ]);

          // ASSERT
          expect(originalFile.existsSync(), isTrue);
          expect(filteredFile.existsSync(), isTrue);
          final filteredFileIncludeFileThatMatchPatterns = Tracefile.parse(
            filteredFile.readAsStringSync(),
          ).includeFileThatMatchPatterns(patterns);
          expect(filteredFileIncludeFileThatMatchPatterns, isFalse);
          for (final fileData in filesDataToBeRemoved) {
            final path = fileData.source.path;
            verify(
              () => out.writeln('<$path> coverage data ignored.'),
            ).called(1);
          }
        },
      );

      test(
        '''

AND a non-existing tracefile to filter
AND a set of patterns to be filtered
WHEN the command is invoqued
THEN an error indicating the issue should be thrown
''',
        () async {
          // ARRANGE
          const patterns = <String>['.g.dart'];
          final absentFilePath = 'absent.lcov.info'.fixturePath;
          final absentFile = File(absentFilePath);
          expect(absentFile.existsSync(), isFalse);

          // ACT
          Future<void> action() => cmdRunner.run([
                filterCmd.name,
                '--${FilterCommand.inputOption}',
                absentFilePath,
                '--${FilterCommand.filtersOption}',
                patterns.join(','),
              ]);

          // ASSERT
          expect(action, throwsA(isA<UsageException>()));
        },
      );
    },
  );
}
