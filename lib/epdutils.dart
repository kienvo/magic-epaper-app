
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

class MagicEpd {
  static const default_req_flags = 0x20;
  static const write_msg_cmd = 0xaa;
  static const read_msg_cmd = 0xac;
  static const read_dyncfg_cmd = 0xad;
  static const write_dyncfg_cmd = 0xae;
  static const ic_mfg_code = 0x02;

  static const epd_cmd = 0x00;
  static const epd_send = 0x01;

  static Future<Uint8List> _transceive(nfcvCmd, Uint8List tagId, Uint8List msg) async
  {
    var b = BytesBuilder();

    b.addByte(default_req_flags);
    b.addByte(nfcvCmd);
    b.addByte(ic_mfg_code);

    b.add(tagId);

    b.addByte(msg.lengthInBytes - 1);
    b.add(msg);

    var raw = b.toBytes();
    print("transceive: ${raw}");

    return await FlutterNfcKit.transceive(raw, timeout: Duration(seconds: 5));
  }

  static Future<Uint8List> _writeMsg(Uint8List tagId, Uint8List msg) async
  {
    return await _transceive(write_msg_cmd, tagId, msg);
  }

  static Future<Uint8List> _readMsg(Uint8List tagId) async
  {
    // Send 0 will return all message present in the tag's mailbox
    return await _transceive(read_msg_cmd, tagId, Uint8List.fromList([0]));
  }

  static Future<Uint8List> _readDynCfg(Uint8List tagId, int address) async
  {
    var b = BytesBuilder();

    b.addByte(default_req_flags);
    b.addByte(read_dyncfg_cmd);
    b.addByte(ic_mfg_code);

    b.add(tagId);

    b.addByte(address);

    var raw = b.toBytes();
    print("read dynamic cfg: ${raw}");

    var result = await FlutterNfcKit.transceive(raw, timeout: Duration(seconds: 5));
    print(result);
    return result;
  }

  static Future<Uint8List> _writeDynCfg(Uint8List tagId, int address, int value) async
  {
    var b = BytesBuilder();

    b.addByte(default_req_flags);
    b.addByte(write_dyncfg_cmd);
    b.addByte(ic_mfg_code);

    b.add(tagId);

    b.addByte(address);
    b.addByte(value);

    var raw = b.toBytes();
    print("write dynamic cfg: ${raw}");

    var result = await FlutterNfcKit.transceive(raw, timeout: Duration(seconds: 5));
    print(result);
    return result;
  }

  static Future<bool> hasI2cGatheredMsg(Uint8List tagId) async
  {
    return ((await _readDynCfg(tagId, 0x0d)).elementAt(1) & 0x04) != 0x04;
  }

  static Future<Uint8List> enableEnergyHarvesting(Uint8List tagId) async
  {
    return await _writeDynCfg(tagId, 0x02, 0x01);
  }

  static void _sleep()
  {
    sleep(Duration(milliseconds: 20));
  }

  static Future<void> wait4msgGathered(Uint8List tagId) async
  {
    var result = false;
    var attempt = 4;
    while (true) {
      try {
        result = await hasI2cGatheredMsg(tagId);
      } catch (e) {
        // This happens when the tag chip is busy, just try to read again
        print("exception ${e}");
        _sleep();
        if (attempt-- <= 0)
          return;
        continue;
      } finally {
        if (result) return;
        _sleep();
      }
    }
  }

  static Future<void> writePixel(Uint8List id, List<Uint8List> chunks, int cmd) async {
    await _writeMsg(id, Uint8List.fromList([epd_cmd, cmd])); // enter transmission 1
    _sleep();
    for (int i = 0; i < chunks.length; i++) {
      Uint8List chunk = chunks[i];
      print("Writing chunk ${i + 1}/${chunks.length} len ${chunk.lengthInBytes}: ${chunk.map((e) => e.toRadixString(16)).toList()}");

      var result = await _writeMsg(id, chunk);
      await wait4msgGathered(id);
    }
    print("All chunks written successfully.");
  }

  static Future<void> writeChunk(List<Uint8List> blackChunks, List<Uint8List> redChunks) async
  {
    var availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      // oh-no
    }

    var tag = await FlutterNfcKit.poll(timeout: Duration(seconds: 5));
    print(jsonEncode(tag));
    var id = Uint8List.fromList(hex.decode(tag.id));

    if (tag.type == NFCTagType.iso15693) {
      // await enableEnergyHarvesting(id);
      // sleep(Duration(seconds: 5));
      await writePixel(id, blackChunks, 0x10);
      await writePixel(id, redChunks, 0x13);
      await _writeMsg(id, Uint8List.fromList([epd_cmd, 0x12])); //refresh
    }
    await FlutterNfcKit.finish();
  }
}