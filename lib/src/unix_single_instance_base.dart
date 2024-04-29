import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
// TODO remove path_provider as it introduces a flutter dependency
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// TODO move to a named arg
const kDebugMode = false;

Future<String> applicationConfigDirectory() async {
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

Future<bool> unixSingleInstance(List<String> arguments,
    void Function(List<dynamic> args) cmdProcessor) async {
  // TODO make a named arg
  // Kept short because of mac os x sandboxing makes the name too long for unix sockets.
  var socketFilename = 'socket';
  // TODO make configurable so it can be per X, per User, or for the whole machine based on optional named args
  var configPath = await applicationConfigDirectory();
  await Directory(configPath).create(recursive: true);
  var socketFilepath = p.join(configPath, socketFilename);
  final InternetAddress host = InternetAddress(socketFilepath, type: InternetAddressType.unix);
  var socketFile = File(socketFilepath);
  if (await socketFile.exists()) {
    if (kDebugMode) {
      print("Found existing instance!");
    }
    var messageSent = await sendArgsToUixSocket(arguments, host);
    if (messageSent) {
      if (kDebugMode) {
        print("Message sent");
        print("Quiting");
      }
      exit(0);
      return false;
    }
    if (kDebugMode) {
      print("Deleting dead socket");
    }
    await socketFile.delete();
  }
  StreamSubscription<Socket> socket;
  try {
    socket = await createUnixSocket(host, cmdProcessor);
  } catch (e) {
    print("Socket create error");
    print(e);
    exit(0);
    return false;
  }
  return true;
}

Future<bool> sendArgsToUixSocket(
    List<String> args, InternetAddress host) async {
  try {
    var s = await Socket.connect(host, 0);
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

Future<StreamSubscription<Socket>> createUnixSocket(InternetAddress host,
    void Function(List<dynamic> args) cmdProcessor) async {
  if (kDebugMode) {
    print("creating socket");
  }
  ServerSocket serverSocket = await ServerSocket.bind(host, 0);
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
