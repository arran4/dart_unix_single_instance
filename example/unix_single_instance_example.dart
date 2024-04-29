import 'dart:io';

import 'package:unix_single_instance/unix_single_instance.dart';

void cmdProcessor(List<dynamic> decodedArgs) {
  if (decodedArgs.isEmpty) {
    // TODO show window?
  }
  for (var each in decodedArgs) {
    if (each is! String) {
      continue;
    }
    // TODO DO SOMETHING
  }
}

void main(List<String> arguments) async {
  if (Platform.isLinux) {
    if (!await unixSingleInstance(arguments, cmdProcessor)) {
      exit(0);
      return;
    }
  } else if (Platform.isMacOS) {
    if (!await unixSingleInstance(arguments, cmdProcessor)) {
      exit(0);
      return;
    }
  }
}
