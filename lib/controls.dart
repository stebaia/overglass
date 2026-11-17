/// System controls placed inside Flutter content: buttons, switches,
/// sliders, date pickers and gauges.
///
/// Kept apart from `package:overglass/overglass.dart` because, unlike the
/// bars, these are platform views on iOS. An app that imports only the main
/// library uses none.
library;

export 'src/controls.dart'
    show
        OverglassButton,
        OverglassButtonSize,
        OverglassButtonStyle,
        OverglassDatePicker,
        OverglassGauge,
        OverglassGaugeStyle,
        OverglassSlider,
        OverglassSwitch;
