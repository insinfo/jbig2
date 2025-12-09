enum CombinationOperator {
  OR,
  AND,
  XOR,
  XNOR,
  REPLACE;

  static CombinationOperator translateOperatorCodeToEnum(
      int combinationOperatorCode) {
    switch (combinationOperatorCode) {
      case 0:
        return OR;
      case 1:
        return AND;
      case 2:
        return XOR;
      case 3:
        return XNOR;
      default:
        return REPLACE;
    }
  }
}
