// Shared by the screenshot generators: --dart-define=SHOT_WIDTH=1024 renders
// at tablet width (default 390, a phone).
const shotWidth = int.fromEnvironment('SHOT_WIDTH', defaultValue: 390);
const shotHeight = shotWidth >= 900 ? 768 : 844;
