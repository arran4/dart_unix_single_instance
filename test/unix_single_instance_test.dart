import 'dart:io';

import 'package:test/test.dart';
import 'package:unix_single_instance/unix_single_instance.dart';
import 'package:path/path.dart' as p;

class MockSocketProvider implements SocketProvider {
  @override
  Future<ServerSocket> bind(InternetAddress address, int port) {
    throw UnimplementedError('Mock bind');
  }

  @override
  Future<Socket> connect(InternetAddress host, int port) {
    throw UnimplementedError('Mock connect');
  }
}

void main() {
  group('unixSingleInstance', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('unix_single_instance_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('First instance returns true', () async {
      var isFirst = await unixSingleInstance(
        ['arg1', 'arg2'],
        (args) {},
        customConfigPath: tempDir.path,
        errorMode: ErrorMode.returnFalse,
      );

      expect(isFirst, isTrue);

      // Verify socket file was created
      var socketFile = File(p.join(tempDir.path, 'socket'));
      expect(await socketFile.exists(), isTrue);
    });

    test('Second instance returns false and sends args to first instance',
        () async {
      var receivedArgs = <dynamic>[];

      // Start the "first instance"
      var isFirst = await unixSingleInstance(
        ['first'],
        (args) {
          receivedArgs.addAll(args);
        },
        customConfigPath: tempDir.path,
        errorMode: ErrorMode.returnFalse,
      );

      expect(isFirst, isTrue);

      // Start the "second instance"
      var isSecondFirst = await unixSingleInstance(
        ['second1', 'second2'],
        (args) {},
        customConfigPath: tempDir.path,
        errorMode: ErrorMode.returnFalse,
      );

      expect(isSecondFirst, isFalse);

      // Give it a moment for the socket to process
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedArgs, equals(['second1', 'second2']));
    });

    test('Second instance triggers exitOverride when provided', () async {
      // Start the "first instance"
      var isFirst = await unixSingleInstance(
        ['first'],
        (args) {},
        customConfigPath: tempDir.path,
        errorMode: ErrorMode.exit,
      );

      expect(isFirst, isTrue);

      int? capturedExitCode;

      // Start the "second instance" with exitOverride
      var isSecondFirst = await unixSingleInstance(
        ['second1', 'second2'],
        (args) {},
        customConfigPath: tempDir.path,
        errorMode: ErrorMode.exit,
        exitOverride: (code) {
          capturedExitCode = code;
        },
      );

      expect(isSecondFirst, isFalse);
      expect(capturedExitCode, equals(0));
    });

    test('Custom SocketProvider is used', () async {
      final mockProvider = MockSocketProvider();

      try {
        await unixSingleInstance(
          ['first'],
          (args) {},
          customConfigPath: tempDir.path,
          errorMode: ErrorMode.throwError,
          socketProvider: mockProvider,
        );
        fail('Expected an exception');
      } catch (e) {
        // We expect it to throw safeToString wrapper over UnimplementedError
        expect(e.toString(), contains('Mock bind'));
      }
    });

    test('Dead socket is deleted and first instance starts', () async {
      // Simulate a dead socket file from a previously crashed instance
      var socketFile = File(p.join(tempDir.path, 'socket'));
      await socketFile.create();

      var isFirst = await unixSingleInstance(
        ['arg1', 'arg2'],
        (args) {},
        customConfigPath: tempDir.path,
        errorMode: ErrorMode.returnFalse,
      );

      // The dead socket should be deleted and it should successfully bind
      expect(isFirst, isTrue);

      // Verify a real, bound socket file now exists
      expect(await socketFile.exists(), isTrue);
    });
  });
}
