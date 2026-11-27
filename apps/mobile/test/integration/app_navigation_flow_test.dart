// Runs the N7 whole-app flow (integration_test/app_navigation_test.dart) as
// an ordinary headless test, since `flutter test integration_test/...` needs
// a connected device. See that file.
import '../../integration_test/app_navigation_test.dart' as flow;

void main() => flow.main();
