import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
// TODO remove path_provider as it introduces a flutter dependency
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Simple function to get the appropriate file location to store using path_provider
// this should be replaced, especially if we are going to allow the user to specify
// if it's a single instance per {user, user&x, x, system, etc.}
Future<String> _applicationConfigDirectory() async {
  final String dbPath;
  if (Platform.isAndroid) {
    dbPath = (await getApplicationDocumentsDirectory()).path;
  } else if (Platform.isLinux || Platform.isWindows) {
    dbPath = (await getApplicationSupportDirectory()).path;
  } else if (Platform.isMacOS || Platform.isIOS) {
    dbPath = (await getApplicationDocumentsDirectory()).path;
  } else {
    dbPath = '';
  }
  return dbPath;
}

abstract class SocketProvider {
  Future<ServerSocket> bind(InternetAddress address, int port);
  Future<Socket> connect(InternetAddress host, int port);
  Future<bool> checkSocketExists(String path);
  Future<void> clearSocket(String path);
}

class DefaultSocketProvider implements SocketProvider {
  @override
  Future<ServerSocket> bind(InternetAddress address, int port) {
    return ServerSocket.bind(address, port);
  }

  @override
  Future<Socket> connect(InternetAddress host, int port) {
    return Socket.connect(host, port);
  }

  @override
  Future<bool> checkSocketExists(String path) {
    return File(path).exists();
  }

  @override
  Future<void> clearSocket(String path) {
    return File(path).delete();
  }
}

enum ErrorMode {
  // Exits with a -1
  exit,
  // Throws an error
  throwError,
  // Returns false
  returnFalse,
  // Returns true
  returnTrue,
}

// Call this at the top of your function, returns a bool. Which is "true" if this is the first instance,
// if this is the second instance (and it has transmitted the arguments across the socket) it returns
// false.
// cmdProcessor is what the first instance does once it receives the command line arguments from the previous
// kDebugMode makes the application noisy.
Future<bool> unixSingleInstance(
  List<String> arguments,
  void Function(List<dynamic> args) cmdProcessor, {
  bool kDebugMode = false,
  ErrorMode errorMode = ErrorMode.exit,
  String? customConfigPath,
  String socketFilename = 'socket',
  void Function(int)? exitOverride,
  SocketProvider? socketProvider,
}) async {
  final provider = socketProvider ?? DefaultSocketProvider();
  // Kept short because of mac os x sandboxing makes the name too long for unix sockets.
  // TODO make configurable so it can be per X, per User, or for the whole machine based on optional named args
  var configPath = customConfigPath ?? await _applicationConfigDirectory();
  await Directory(configPath).create(recursive: true);
  var socketFilepath = p.join(configPath, socketFilename);
  final InternetAddress host = InternetAddress(
    socketFilepath,
    type: InternetAddressType.unix,
  );
  if (await provider.checkSocketExists(socketFilepath)) {
    if (kDebugMode) {
      print("Found existing instance!");
    }
    var messageSent = await _sendArgsToUixSocket(
      arguments,
      host,
      provider,
      kDebugMode: kDebugMode,
    );
    if (messageSent) {
      if (kDebugMode) {
        print("Message sent");
        print("Quiting");
      }
      if (errorMode == ErrorMode.returnFalse) {
        return false;
      } else {
        if (exitOverride != null) {
          exitOverride(0);
          return false;
        }
        exit(0);
      }
    } else {
      if (kDebugMode) {
        print("Deleting dead socket");
      }
      await provider.clearSocket(socketFilepath);
    }
  }
  // TODO manage socket subscription, technically not required because OS clean up does the work "for" us but good practices.
  // StreamSubscription<Socket>? socket;
  try {
    /*socket = */
    await _createUnixSocket(
      host,
      cmdProcessor,
      provider,
      kDebugMode: kDebugMode,
    );
  } catch (e) {
    print("Socket create error");
    print(e);
    switch (errorMode) {
      case ErrorMode.exit:
        if (exitOverride != null) {
          exitOverride(-1);
          return false;
        }
        exit(-1);
      case ErrorMode.throwError:
        throw Error.safeToString("socket create error: $e");
      case ErrorMode.returnTrue:
        return true;
      case ErrorMode.returnFalse:
      // Pass through
    }
    return false;
  }
  return true;
}

// JSON serializes the args, and sends across "the wire"
Future<bool> _sendArgsToUixSocket(
  List<String> args,
  InternetAddress host,
  SocketProvider provider, {
  bool kDebugMode = false,
}) async {
  try {
    var s = await provider.connect(host, 0);
    s.writeln(jsonEncode(args));
    await s.close();
    return true;
  } catch (e) {
    if (kDebugMode) {
      print("Socket connect error");
      print(e);
    }
    return false;
  }
}

// Creates the unix socket, or cleans up if it exists but isn't valid and then
// recursively calls itself -- if the socket is valid, sends the args as json.
// Return stream subscription.
Future<StreamSubscription<Socket>> _createUnixSocket(
  InternetAddress host,
  void Function(List<dynamic> args) cmdProcessor,
  SocketProvider provider, {
  bool kDebugMode = false,
}) async {
  if (kDebugMode) {
    print("creating socket");
  }
  ServerSocket serverSocket = await provider.bind(host, 0);
  if (kDebugMode) {
    print("creating listening");
  }
  var stream = serverSocket.listen((event) async {
    if (kDebugMode) {
      print("Event");
      print(event);
    }
    const utf8decoder = Utf8Decoder();
    var args = StringBuffer();
    await event.forEach((Uint8List element) {
      args.write(utf8decoder.convert(element));
    });
    if (kDebugMode) {
      print("Second instance launched with: ${args.toString()}");
    }
    try {
      List<dynamic> decodedArgs = jsonDecode(args.toString());
      cmdProcessor(decodedArgs);
    } catch (e) {
      print(e);
    }
  });
  return stream;
}
