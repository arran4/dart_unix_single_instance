# Unix Single Instance

Restrict a Linux or Mac OS X app to only be able to open one instance at a time. (Currently per user)

This uses Unix sockets to ensure a single instance. There are other ways of doing this however this was
the most "portable." For windows support cosnider adding: windows_single_instance

## Installing

1. Add the `async` modifier to your apps `main` function.
1. Write a function `cmdProcessor(List<dynamic> decodedArgs)` which re-processes command line options
1. Add a call to `unixSingleInstance()` inside the appropriate conditions. Placement in the main function
to taste.

## Notes

If using flutter, recommend using this with the: `window_manager` plugin

### Future expansion

Currently it is on a per-user basis and ignores multiple displays. It could be greatly improved with
options which allow you to toggle if it's per X, per user, etc. (If per X and per user and for linux only
consider using dbus -- not a strong recommendation.)

## Example

```
import 'package:unix_single_instance/unix_single_instance.dart';

void main(List<String> args) async {
    WidgetsFlutterBinding.ensureInitialized();
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
    runApp(const MyApp());
}

void cmdProcessor(List<dynamic> decodedArgs) {
  if (decodedArgs.isEmpty && !Platform.isWindows) {
    windowManager.waitUntilReadyToShow(null, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  for (var each in decodedArgs) {
    if (each is! String) {
      continue;
    }
    queueUrl(each);
  }
}

```
