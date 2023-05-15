library eventsource.src.decoder;

import "dart:async";
import "dart:convert";

import "event.dart";

typedef RetryIndicator = void Function(Duration retry);

class EventSourceDecoder implements StreamTransformer<List<int>, Event> {
  RetryIndicator? retryIndicator;

  EventSourceDecoder({this.retryIndicator});

  Stream<Event> bind(Stream<List<int>> stream) {
    late StreamController<Event> controller;
    controller = new StreamController(onListen: () {
      // the event we are currently building
      Event currentEvent = new Event();
      // This stream will receive chunks of data that is not necessarily a
      // single event. So we build events on the fly and broadcast the event as
      // soon as we encounter a double newline, then we start a new one.
      stream
          .transform(new Utf8Decoder())
          .transform(new LineSplitter())
          .listen((String line) {
        if (line.isEmpty) {
          // event is done
          // strip ending newline from data
          if (currentEvent.data != null && currentEvent.data!.endsWith('\n')) {
            currentEvent.data = currentEvent.data!.substring(0, currentEvent.data!.length - 1);
          }
          controller.add(currentEvent);
          currentEvent = new Event();
          return;
        }
        // split the line into field and value
        int colonPos = line.indexOf(':');
        String? field;
        String? value = '';
        if (colonPos == -1) {
          field = line;
        } else {
          field = line.substring(0, colonPos);
          if (line.length > colonPos + 1) {
            value = line.substring(colonPos + 1);
            if (value.startsWith(' ')) {
              value = value.substring(1);
            }
          }
        }
        if (field.isEmpty) {
          // lines starting with a colon are to be ignored
          return;
        }
        switch (field) {
          case "event":
            currentEvent.event = value;
            break;
          case "data":
            currentEvent.data = (currentEvent.data ?? "") + value + "\n";
            break;
          case "id":
            currentEvent.id = value;
            break;
          case "retry":
            retryIndicator?.call(new Duration(milliseconds: int.parse(value)));
            break;
        }
      });
    });
    return controller.stream;
  }

  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<List<int>, Event, RS, RT>(this);
}
