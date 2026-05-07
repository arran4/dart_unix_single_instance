import 'dart:ffi';
import 'dart:io';

final DynamicLibrary _libc = DynamicLibrary.process();

typedef _SocketC = Int32 Function(Int32 domain, Int32 type, Int32 protocol);
typedef _SocketDart = int Function(int domain, int type, int protocol);
final _SocketDart _cSocket = _libc.lookupFunction<_SocketC, _SocketDart>(
  'socket',
);

typedef _BindC = Int32 Function(Int32 fd, Pointer<Uint8> addr, Uint32 len);
typedef _BindDart = int Function(int fd, Pointer<Uint8> addr, int len);
final _BindDart _cBind = _libc.lookupFunction<_BindC, _BindDart>('bind');

typedef _AcceptC =
    Int32 Function(Int32 fd, Pointer<Uint8> addr, Pointer<Uint32> len);
typedef _AcceptDart =
    int Function(int fd, Pointer<Uint8> addr, Pointer<Uint32> len);
final _AcceptDart _cAccept = _libc.lookupFunction<_AcceptC, _AcceptDart>(
  'accept',
);

typedef _ReadC = IntPtr Function(Int32 fd, Pointer<Uint8> buf, IntPtr count);
typedef _ReadDart = int Function(int fd, Pointer<Uint8> buf, int count);
final _ReadDart _cRead = _libc.lookupFunction<_ReadC, _ReadDart>('read');

typedef _CloseC = Int32 Function(Int32 fd);
typedef _CloseDart = int Function(int fd);
final _CloseDart _cClose = _libc.lookupFunction<_CloseC, _CloseDart>('close');

typedef _SetsockoptC =
    Int32 Function(
      Int32 fd,
      Int32 level,
      Int32 optname,
      Pointer<Uint8> optval,
      Uint32 optlen,
    );
typedef _SetsockoptDart =
    int Function(
      int fd,
      int level,
      int optname,
      Pointer<Uint8> optval,
      int optlen,
    );
final _SetsockoptDart _cSetsockopt = _libc
    .lookupFunction<_SetsockoptC, _SetsockoptDart>('setsockopt');

typedef _SendmsgC = IntPtr Function(Int32 fd, Pointer<Uint8> msg, Int32 flags);
typedef _SendmsgDart = int Function(int fd, Pointer<Uint8> msg, int flags);
final _SendmsgDart _cSendmsg = _libc.lookupFunction<_SendmsgC, _SendmsgDart>(
  'sendmsg',
);

typedef _CallocC = Pointer<Uint8> Function(IntPtr num, IntPtr size);
typedef _CallocDart = Pointer<Uint8> Function(int num, int size);
final _CallocDart _cCalloc = _libc.lookupFunction<_CallocC, _CallocDart>(
  'calloc',
);

typedef _FreeC = Void Function(Pointer<Uint8> ptr);
typedef _FreeDart = void Function(Pointer<Uint8> ptr);
final _FreeDart _cFree = _libc.lookupFunction<_FreeC, _FreeDart>('free');

const int _afAlg = 38;
const int _sockSeqpacket = 5;
const int _solAlg = 279;
const int _algSetKey = 1;
const int _algSetIv = 2;
const int _algSetOp = 3;
const int _algOpDecrypt = 0;
const int _algOpEncrypt = 1;

class AfAlgEncryptor {
  final List<int> key;
  final bool isSupported = Platform.isLinux;

  AfAlgEncryptor(this.key);

  List<int> process(
    List<int> data,
    bool encrypt, {
    String algType = "skcipher",
    String algName = "cbc(aes)",
  }) {
    if (!isSupported) {
      return data; // Fallback if not supported
    }

    int fd = _cSocket(_afAlg, _sockSeqpacket, 0);
    if (fd < 0) return data;

    Pointer<Uint8> sa = _cCalloc(88, 1);
    if (sa == nullptr) {
      _cClose(fd);
      return data;
    }

    try {
      sa[0] = _afAlg;
      sa[1] = 0;
      for (int i = 0; i < algType.length && i < 14; i++) {
        sa[2 + i] = algType.codeUnitAt(i);
      }
      sa[2 + algType.length] = 0;
      for (int i = 0; i < algName.length && i < 64; i++) {
        sa[22 + i] = algName.codeUnitAt(i);
      }
      sa[22 + algName.length] = 0;

      if (_cBind(fd, sa, 88) < 0) return data;

      Pointer<Uint8> keyPtr = _cCalloc(key.length, 1);
      for (int i = 0; i < key.length; i++) {
        keyPtr[i] = key[i];
      }
      if (_cSetsockopt(fd, _solAlg, _algSetKey, keyPtr, key.length) < 0) {
        _cFree(keyPtr);
        return data;
      }
      _cFree(keyPtr);

      int opfd = _cAccept(fd, nullptr, nullptr);
      if (opfd < 0) return data;

      try {
        // Pad data to multiple of 16 for AES
        int paddedLen = data.length;
        if (paddedLen % 16 != 0) {
          paddedLen += 16 - (paddedLen % 16);
        }

        Pointer<Uint8> buf = _cCalloc(paddedLen, 1);
        for (int i = 0; i < data.length; i++) {
          buf[i] = data[i];
        }

        Pointer<Uint8> iov = _cCalloc(
          16,
          1,
        ); // struct iovec (8 bytes for ptr, 8 for len on 64-bit)
        Pointer<Pointer<Uint8>> iovBase = iov.cast();
        iovBase[0] = buf;
        Pointer<Uint64> iovLen = Pointer.fromAddress(iov.address + 8).cast();
        iovLen[0] = paddedLen;

        // control message buffer
        int cmsgSpaceOp = 24; // CMSG_SPACE(4)
        int cmsgSpaceIv = 40; // CMSG_SPACE(20)
        Pointer<Uint8> cbuf = _cCalloc(cmsgSpaceOp + cmsgSpaceIv, 1);

        // First cmsghdr
        Pointer<Uint64> cmsg1Len = cbuf.cast();
        cmsg1Len[0] = 20; // CMSG_LEN(4)
        Pointer<Int32> cmsg1Level = Pointer.fromAddress(
          cbuf.address + 8,
        ).cast();
        cmsg1Level[0] = _solAlg;
        Pointer<Int32> cmsg1Type = Pointer.fromAddress(
          cbuf.address + 12,
        ).cast();
        cmsg1Type[0] = _algSetOp;
        Pointer<Uint32> cmsg1Data = Pointer.fromAddress(
          cbuf.address + 16,
        ).cast();
        cmsg1Data[0] = encrypt ? _algOpEncrypt : _algOpDecrypt;

        // Second cmsghdr
        int offset = cmsgSpaceOp;
        Pointer<Uint64> cmsg2Len = Pointer.fromAddress(
          cbuf.address + offset,
        ).cast();
        cmsg2Len[0] = 36; // CMSG_LEN(20)
        Pointer<Int32> cmsg2Level = Pointer.fromAddress(
          cbuf.address + offset + 8,
        ).cast();
        cmsg2Level[0] = _solAlg;
        Pointer<Int32> cmsg2Type = Pointer.fromAddress(
          cbuf.address + offset + 12,
        ).cast();
        cmsg2Type[0] = _algSetIv;

        Pointer<Uint32> ivLen = Pointer.fromAddress(
          cbuf.address + offset + 16,
        ).cast();
        ivLen[0] = 16;
        Pointer<Uint8> ivData = Pointer.fromAddress(
          cbuf.address + offset + 20,
        ).cast();
        for (int i = 0; i < 16; i++) {
          ivData[i] = 0; // null IV for simplicity
        }

        // msghdr
        Pointer<Uint8> msg = _cCalloc(
          56,
          1,
        ); // struct msghdr is 56 bytes on 64-bit linux
        Pointer<Pointer<Uint8>> msgIov = Pointer.fromAddress(
          msg.address + 16,
        ).cast();
        msgIov[0] = iov;
        Pointer<Uint64> msgIovlen = Pointer.fromAddress(
          msg.address + 24,
        ).cast();
        msgIovlen[0] = 1;
        Pointer<Pointer<Uint8>> msgControl = Pointer.fromAddress(
          msg.address + 32,
        ).cast();
        msgControl[0] = cbuf;
        Pointer<Uint64> msgControllen = Pointer.fromAddress(
          msg.address + 40,
        ).cast();
        msgControllen[0] = cmsgSpaceOp + cmsgSpaceIv;

        int w = _cSendmsg(opfd, msg, 0);

        _cFree(msg);
        _cFree(cbuf);
        _cFree(iov);

        if (w < 0) {
          _cFree(buf);
          return data;
        }

        Pointer<Uint8> out = _cCalloc(paddedLen, 1);
        int r = _cRead(opfd, out, paddedLen);

        if (r > 0) {
          List<int> result = [];
          for (int i = 0; i < r; i++) {
            result.add(out[i]);
          }

          if (!encrypt) {
            // Remove padding
            int actualLen = r;
            while (actualLen > 0 && result[actualLen - 1] == 0) {
              actualLen--;
            }
            result = result.sublist(0, actualLen);
          }

          _cFree(out);
          _cFree(buf);
          return result;
        }

        _cFree(out);
        _cFree(buf);
        return data;
      } finally {
        _cClose(opfd);
      }
    } finally {
      _cFree(sa);
      _cClose(fd);
    }
  }
}
