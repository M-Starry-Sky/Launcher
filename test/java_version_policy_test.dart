import 'package:flutter_test/flutter_test.dart';
import 'package:xingqiong_launcher/core/perf/java_env_adapter.dart';

void main() {
  group('JavaVersionPolicy.requiredMajor', () {
    test('1.20.4 stays on Java 17', () {
      expect(JavaVersionPolicy.requiredMajor('1.20.4'), 17);
    });

    test('1.20.5+ needs Java 21', () {
      expect(JavaVersionPolicy.requiredMajor('1.20.5'), 21);
      expect(JavaVersionPolicy.requiredMajor('1.20.6'), 21);
    });

    test('1.21.x always needs Java 21 (not only patch>=5)', () {
      expect(JavaVersionPolicy.requiredMajor('1.21'), 21);
      expect(JavaVersionPolicy.requiredMajor('1.21.0'), 21);
      expect(JavaVersionPolicy.requiredMajor('1.21.1'), 21);
      expect(JavaVersionPolicy.requiredMajor('1.21.4'), 21);
      expect(JavaVersionPolicy.requiredMajor('1.21.5'), 21);
    });

    test('future 1.22 needs Java 21', () {
      expect(JavaVersionPolicy.requiredMajor('1.22'), 21);
      expect(JavaVersionPolicy.requiredMajor('1.22.0'), 21);
    });

    test('snapshots default to Java 21', () {
      expect(JavaVersionPolicy.requiredMajor('25w14a'), 21);
      expect(JavaVersionPolicy.requiredMajor('24w46a'), 21);
    });

    test('meta major overrides heuristic', () {
      expect(JavaVersionPolicy.requiredMajor('1.20.1', fromMeta: 21), 21);
      expect(JavaVersionPolicy.requiredMajor('1.21.4', fromMeta: 21), 21);
    });

    test('fabric profile id still resolves MC version', () {
      expect(
        JavaVersionPolicy.requiredMajor('fabric-loader-0.16.14-1.21.4'),
        21,
      );
      expect(
        JavaVersionPolicy.requiredMajor('fabric-loader-0.15.11-1.20.1'),
        17,
      );
    });
  });
}
