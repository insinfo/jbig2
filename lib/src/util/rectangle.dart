class Rectangle {
  final int x;
  final int y;
  final int width;
  final int height;

  const Rectangle(this.x, this.y, this.width, this.height);

  int get maxX => x + width;
  int get maxY => y + height;
}
