class Music {
  String name;
  Music(this.name);
}

class Queue {
  final List<Music> _queue = []; // fifo

  void enqueue(Music music) => _queue.add(music);

  void dequeue() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0);
    } else {
      print("La cola está vacía");
    }
  }

  List<Music> currentQueue() => List.from(_queue);

  Music? peek() => _queue.isNotEmpty ? _queue.first : null;
}

void main() {
  var q = Queue();

  q.enqueue(Music("IVE - After LIKE"));
  q.enqueue(Music("IVE - IAM"));
  q.enqueue(Music("TWICE - I CAN'T STOP ME"));
  q.enqueue(Music("ILLIT - Do the dance"));

  print("Initial queue:");
  for (var i in q.currentQueue()) {
    print(i.name);
  }

  q.dequeue();
  print("\n------------current queue-------------- \n");
  for (var i in q.currentQueue()) {
    print(i.name);
  }

  print("\nNext song: ${q.peek()?.name}");
}
