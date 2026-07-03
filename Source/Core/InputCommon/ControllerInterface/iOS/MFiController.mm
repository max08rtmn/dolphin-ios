// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "InputCommon/ControllerInterface/iOS/MFiController.h"

#include "InputCommon/ControllerInterface/iOS/Motor.h"
#include "InputCommon/ControllerInterface/ControllerInterface.h"

namespace ciface::iOS
{
static GCControllerButtonInput* FindPhysicalButton(GCController* controller, NSArray<NSString*>* names)
{
  if (@available(iOS 14.0, *))
  {
    NSDictionary<NSString*, GCControllerButtonInput*>* buttons = controller.physicalInputProfile.buttons;
    for (NSString* name in names)
    {
      GCControllerButtonInput* button = buttons[name];
      if (button != nil)
        return button;
    }
  }

  return nil;
}

static GCControllerButtonInput* FindPhysicalButtonContaining(GCController* controller,
                                                             NSArray<NSString*>* name_parts)
{
  if (@available(iOS 14.0, *))
  {
    NSDictionary<NSString*, GCControllerButtonInput*>* buttons = controller.physicalInputProfile.buttons;
    for (NSString* name in buttons)
    {
      for (NSString* name_part in name_parts)
      {
        if ([name rangeOfString:name_part options:NSCaseInsensitiveSearch].location != NSNotFound)
          return buttons[name];
      }
    }
  }

  return nil;
}

static GCControllerButtonInput* FindPhysicalButtonFlexible(GCController* controller,
                                                           NSArray<NSString*>* names,
                                                           NSArray<NSString*>* name_parts)
{
  GCControllerButtonInput* button = FindPhysicalButton(controller, names);
  if (button != nil)
    return button;

  return FindPhysicalButtonContaining(controller, name_parts);
}

static bool HasSeparatedJoyConPhysicalButtons(GCController* controller)
{
  NSString* vendor_name = controller.vendorName;
  const bool looks_like_joycon = vendor_name != nil &&
                                 ([vendor_name rangeOfString:@"Joy-Con"
                                                     options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                  [vendor_name rangeOfString:@"Joycon"
                                                     options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                  [vendor_name rangeOfString:@"Nintendo"
                                                     options:NSCaseInsensitiveSearch].location != NSNotFound);

  const bool has_small_shoulder =
      FindPhysicalButtonFlexible(controller, @[ @"Button SL", @"SL", @"Left SL", @"L SL" ],
                                 @[ @"SL" ]) != nil ||
      FindPhysicalButtonFlexible(controller, @[ @"Button SR", @"SR", @"Right SR", @"R SR" ],
                                 @[ @"SR" ]) != nil;

  const bool has_face_button = FindPhysicalButton(controller, @[ @"Button A", @"A" ]) != nil ||
                               FindPhysicalButton(controller, @[ @"Button B", @"B" ]) != nil ||
                               FindPhysicalButton(controller, @[ @"Button X", @"X" ]) != nil ||
                               FindPhysicalButton(controller, @[ @"Button Y", @"Y" ]) != nil;
  const bool looks_like_separated_micro_gamepad =
      controller.microGamepad != nil && has_face_button && controller.extendedGamepad == nil;

  if (!looks_like_joycon && !has_small_shoulder && !looks_like_separated_micro_gamepad)
    return false;

  const bool looks_like_pair = vendor_name != nil &&
                               ([vendor_name rangeOfString:@"L/R"
                                                   options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                [vendor_name rangeOfString:@"Pair"
                                                   options:NSCaseInsensitiveSearch].location != NSNotFound);
  if (looks_like_pair)
    return false;

  return has_face_button || has_small_shoulder;
}

MFiController::MFiController(GCController* controller) : m_controller(controller)
{
  const auto add_physical_button = [this, controller](NSArray<NSString*>* names,
                                                     const std::string& input_name) -> bool {
    GCControllerButtonInput* button = FindPhysicalButton(controller, names);
    if (button != nil)
    {
      AddInput(new Button(button, input_name));
      return true;
    }

    return false;
  };

  const auto add_flexible_physical_button =
      [this, controller](NSArray<NSString*>* names, NSArray<NSString*>* name_parts,
                         const std::string& input_name) -> bool {
    GCControllerButtonInput* button = FindPhysicalButtonFlexible(controller, names, name_parts);
    if (button != nil)
    {
      AddInput(new Button(button, input_name));
      return true;
    }

    return false;
  };

  const auto add_raw_physical_buttons = [this, controller] {
    if (@available(iOS 14.0, *))
    {
      NSDictionary<NSString*, GCControllerButtonInput*>* buttons = controller.physicalInputProfile.buttons;
      for (NSString* name in buttons)
      {
        GCControllerButtonInput* button = buttons[name];
        const char* name_c_string = [name UTF8String];
        if (button != nil && name_c_string != nullptr)
          AddInput(new Button(button, std::string("Raw ") + name_c_string));
      }
    }
  };

  if (HasSeparatedJoyConPhysicalButtons(controller))
  {
    add_physical_button(@[ @"Button A", @"A" ], "Button A");
    add_physical_button(@[ @"Button B", @"B" ], "Button B");
    add_physical_button(@[ @"Button X", @"X" ], "Button X");
    add_physical_button(@[ @"Button Y", @"Y" ], "Button Y");

    const bool has_dpad_up =
        add_physical_button(@[ @"Direction Pad Up", @"Dpad Up", @"D-Pad Up" ], "D-Pad Up");
    const bool has_dpad_down =
        add_physical_button(@[ @"Direction Pad Down", @"Dpad Down", @"D-Pad Down" ], "D-Pad Down");
    const bool has_dpad_left =
        add_physical_button(@[ @"Direction Pad Left", @"Dpad Left", @"D-Pad Left" ], "D-Pad Left");
    const bool has_dpad_right =
        add_physical_button(@[ @"Direction Pad Right", @"Dpad Right", @"D-Pad Right" ], "D-Pad Right");

    GCExtendedGamepad* separated_extended_gamepad = controller.extendedGamepad;

    bool has_left_shoulder = add_flexible_physical_button(
        @[ @"Left Shoulder", @"Left Shoulder Button", @"Left Bumper", @"Button L", @"L Button",
           @"L", @"L1" ],
        @[ @"Left Shoulder", @"Left Bumper", @"Button L", @"L Button", @"L1" ], "L Shoulder");
    bool has_right_shoulder = add_flexible_physical_button(
        @[ @"Right Shoulder", @"Right Shoulder Button", @"Right Bumper", @"Button R", @"R Button",
           @"R", @"R1" ],
        @[ @"Right Shoulder", @"Right Bumper", @"Button R", @"R Button", @"R1" ], "R Shoulder");

    if (!has_left_shoulder && separated_extended_gamepad.leftShoulder != nil)
    {
      AddInput(new PressureSensitiveButton(separated_extended_gamepad.leftShoulder, "L Shoulder"));
      has_left_shoulder = true;
    }
    if (!has_right_shoulder && separated_extended_gamepad.rightShoulder != nil)
    {
      AddInput(new PressureSensitiveButton(separated_extended_gamepad.rightShoulder, "R Shoulder"));
      has_right_shoulder = true;
    }

    GCControllerButtonInput* left_small_shoulder = FindPhysicalButtonFlexible(
        controller, @[ @"Button SL", @"SL", @"Left SL", @"L SL" ], @[ @"SL" ]);
    if (left_small_shoulder != nil)
    {
      AddInput(new Button(left_small_shoulder, "SL"));
      AddInput(new Button(left_small_shoulder, "L Small Shoulder"));
    }

    GCControllerButtonInput* right_small_shoulder = FindPhysicalButtonFlexible(
        controller, @[ @"Button SR", @"SR", @"Right SR", @"R SR" ], @[ @"SR" ]);
    if (right_small_shoulder != nil)
    {
      AddInput(new Button(right_small_shoulder, "SR"));
      AddInput(new Button(right_small_shoulder, "R Small Shoulder"));
    }

    bool has_left_trigger = add_flexible_physical_button(
        @[ @"Left Trigger", @"Left Trigger Button", @"Button ZL", @"ZL", @"L2" ],
        @[ @"Left Trigger", @"Button ZL", @"ZL", @"L2" ], "L Trigger");
    bool has_right_trigger = add_flexible_physical_button(
        @[ @"Right Trigger", @"Right Trigger Button", @"Button ZR", @"ZR", @"R2" ],
        @[ @"Right Trigger", @"Button ZR", @"ZR", @"R2" ], "R Trigger");

    if (!has_left_trigger && separated_extended_gamepad.leftTrigger != nil)
    {
      AddInput(new PressureSensitiveButton(separated_extended_gamepad.leftTrigger, "L Trigger"));
      has_left_trigger = true;
    }
    if (!has_right_trigger && separated_extended_gamepad.rightTrigger != nil)
    {
      AddInput(new PressureSensitiveButton(separated_extended_gamepad.rightTrigger, "R Trigger"));
      has_right_trigger = true;
    }

    if (!has_left_trigger && left_small_shoulder != nil)
      AddInput(new Button(left_small_shoulder, "L Trigger"));
    if (!has_right_trigger && right_small_shoulder != nil)
      AddInput(new Button(right_small_shoulder, "R Trigger"));

    bool has_menu = add_flexible_physical_button(
        @[ @"Button Menu", @"Menu", @"Button Plus", @"Plus", @"+" ],
        @[ @"Button Menu", @"Menu", @"Button Plus", @"Plus" ], "Menu");
    bool has_options = add_flexible_physical_button(
        @[ @"Button Options", @"Options", @"Button Minus", @"Minus", @"-" ],
        @[ @"Button Options", @"Options", @"Button Minus", @"Minus" ], "Options");
    bool has_home = add_flexible_physical_button(
        @[ @"Button Home", @"Home", @"Button Guide", @"Guide", @"System" ],
        @[ @"Home", @"Guide", @"System" ], "Home");
    bool has_capture = add_flexible_physical_button(
        @[ @"Button Capture", @"Capture", @"Button Screenshot", @"Screenshot", @"Button Share",
           @"Share", @"Button Create", @"Create" ],
        @[ @"Capture", @"Screenshot", @"Share", @"Create" ], "Capture");
    bool has_screenshot = add_flexible_physical_button(
        @[ @"Button Capture", @"Capture", @"Button Screenshot", @"Screenshot", @"Button Share",
           @"Share", @"Button Create", @"Create" ],
        @[ @"Capture", @"Screenshot", @"Share", @"Create" ], "Screenshot");
    (void)has_capture;
    (void)has_screenshot;

    if (!has_menu && separated_extended_gamepad.buttonMenu != nil)
      AddInput(new Button(separated_extended_gamepad.buttonMenu, "Menu"));
    if (!has_options && separated_extended_gamepad.buttonOptions != nil)
      AddInput(new Button(separated_extended_gamepad.buttonOptions, "Options"));
    if (!has_home && separated_extended_gamepad.buttonHome != nil)
      AddInput(new Button(separated_extended_gamepad.buttonHome, "Home"));

    if (controller.microGamepad != nil)
    {
      GCMicroGamepad* gamepad = controller.microGamepad;
      if (!has_dpad_up)
        AddInput(new Button(gamepad.dpad.up, "D-Pad Up"));
      if (!has_dpad_down)
        AddInput(new Button(gamepad.dpad.down, "D-Pad Down"));
      if (!has_dpad_left)
        AddInput(new Button(gamepad.dpad.left, "D-Pad Left"));
      if (!has_dpad_right)
        AddInput(new Button(gamepad.dpad.right, "D-Pad Right"));
    }
  }
  else if (controller.extendedGamepad != nil)
  {
    GCExtendedGamepad* gamepad = controller.extendedGamepad;
    AddInput(new Button(gamepad.buttonA, "Button A"));
    AddInput(new Button(gamepad.buttonB, "Button B"));
    AddInput(new Button(gamepad.buttonX, "Button X"));
    AddInput(new Button(gamepad.buttonY, "Button Y"));
    AddInput(new Button(gamepad.dpad.up, "D-Pad Up"));
    AddInput(new Button(gamepad.dpad.down, "D-Pad Down"));
    AddInput(new Button(gamepad.dpad.left, "D-Pad Left"));
    AddInput(new Button(gamepad.dpad.right, "D-Pad Right"));
    GCControllerButtonInput* left_shoulder =
        FindPhysicalButton(controller, @[ @"Left Shoulder", @"Left Shoulder Button", @"Left Bumper",
                                          @"Button L", @"L", @"L1" ]);
    if (left_shoulder == nil)
      left_shoulder = gamepad.leftShoulder;

    GCControllerButtonInput* right_shoulder =
        FindPhysicalButton(controller, @[ @"Right Shoulder", @"Right Shoulder Button", @"Right Bumper",
                                          @"Button R", @"R", @"R1" ]);
    if (right_shoulder == nil)
      right_shoulder = gamepad.rightShoulder;

    GCControllerButtonInput* left_trigger =
        FindPhysicalButton(controller, @[ @"Left Trigger", @"Left Trigger Button", @"Button ZL", @"ZL",
                                          @"L2" ]);
    if (left_trigger == nil)
      left_trigger = gamepad.leftTrigger;

    GCControllerButtonInput* right_trigger =
        FindPhysicalButton(controller, @[ @"Right Trigger", @"Right Trigger Button", @"Button ZR", @"ZR",
                                          @"R2" ]);
    if (right_trigger == nil)
      right_trigger = gamepad.rightTrigger;

    AddInput(new PressureSensitiveButton(left_shoulder, "L Shoulder"));
    AddInput(new PressureSensitiveButton(right_shoulder, "R Shoulder"));
    AddInput(new PressureSensitiveButton(left_trigger, "L Trigger"));
    AddInput(new PressureSensitiveButton(right_trigger, "R Trigger"));
    AddInput(new Axis(gamepad.leftThumbstick.xAxis, 1.0f, "L Stick X+"));
    AddInput(new Axis(gamepad.leftThumbstick.xAxis, -1.0f, "L Stick X-"));
    AddInput(new Axis(gamepad.leftThumbstick.yAxis, 1.0f, "L Stick Y+"));
    AddInput(new Axis(gamepad.leftThumbstick.yAxis, -1.0f, "L Stick Y-"));
    AddInput(new Axis(gamepad.rightThumbstick.xAxis, 1.0f, "R Stick X+"));
    AddInput(new Axis(gamepad.rightThumbstick.xAxis, -1.0f, "R Stick X-"));
    AddInput(new Axis(gamepad.rightThumbstick.yAxis, 1.0f, "R Stick Y+"));
    AddInput(new Axis(gamepad.rightThumbstick.yAxis, -1.0f, "R Stick Y-"));

    // Optionals and buttons only on newer iOS versions

    if (@available(iOS 14.5, *))
    {
      if ([gamepad isKindOfClass:[GCDualSenseGamepad class]])
      {
        GCDualSenseGamepad* ds_gamepad = (GCDualSenseGamepad*)gamepad;
        AddInput(new Button(ds_gamepad.touchpadButton, "Touchpad"));
        
        // The user's first finger on the touchpad.
        AddInput(new Axis(ds_gamepad.touchpadPrimary.xAxis, 1.0f, "Touchpad X+"));
        AddInput(new Axis(ds_gamepad.touchpadPrimary.xAxis, -1.0f, "Touchpad X-"));
        AddInput(new Axis(ds_gamepad.touchpadPrimary.yAxis, 1.0f, "Touchpad Y+"));
        AddInput(new Axis(ds_gamepad.touchpadPrimary.yAxis, -1.0f, "Touchpad Y-"));

        // The user's second finger on the touchpad.
        AddInput(new Axis(ds_gamepad.touchpadSecondary.xAxis, 1.0f, "Touchpad Secondary X+"));
        AddInput(new Axis(ds_gamepad.touchpadSecondary.xAxis, -1.0f, "Touchpad Secondary X-"));
        AddInput(new Axis(ds_gamepad.touchpadSecondary.yAxis, 1.0f, "Touchpad Secondary Y+"));
        AddInput(new Axis(ds_gamepad.touchpadSecondary.yAxis, -1.0f, "Touchpad Secondary Y-"));
      }
    }

    GCControllerButtonInput* home_button =
        FindPhysicalButtonFlexible(controller, @[ @"Button Home", @"Home" ], @[ @"Home" ]);
    if (home_button != nil)
    {
      AddInput(new Button(home_button, "Home"));
    }
    else if (gamepad.buttonHome != nil)
    {
      AddInput(new Button(gamepad.buttonHome, "Home"));
    }

    add_flexible_physical_button(@[ @"Button Capture", @"Capture", @"Button Screenshot",
                                    @"Screenshot", @"Button Share", @"Share" ],
                                 @[ @"Capture", @"Screenshot", @"Share" ], "Capture");
    add_flexible_physical_button(@[ @"Button Capture", @"Capture", @"Button Screenshot",
                                    @"Screenshot", @"Button Share", @"Share" ],
                                 @[ @"Capture", @"Screenshot", @"Share" ], "Screenshot");
    
    if ([gamepad isKindOfClass:[GCDualShockGamepad class]])
    {
      GCDualShockGamepad* ds_gamepad = (GCDualShockGamepad*)gamepad;
      AddInput(new Button(ds_gamepad.touchpadButton, "Touchpad"));
      
      // The user's first finger on the touchpad.
      AddInput(new Axis(ds_gamepad.touchpadPrimary.xAxis, 1.0f, "Touchpad X+"));
      AddInput(new Axis(ds_gamepad.touchpadPrimary.xAxis, -1.0f, "Touchpad X-"));
      AddInput(new Axis(ds_gamepad.touchpadPrimary.yAxis, 1.0f, "Touchpad Y+"));
      AddInput(new Axis(ds_gamepad.touchpadPrimary.yAxis, -1.0f, "Touchpad Y-"));

      // The user's second finger on the touchpad.
      AddInput(new Axis(ds_gamepad.touchpadSecondary.xAxis, 1.0f, "Touchpad Secondary X+"));
      AddInput(new Axis(ds_gamepad.touchpadSecondary.xAxis, -1.0f, "Touchpad Secondary X-"));
      AddInput(new Axis(ds_gamepad.touchpadSecondary.yAxis, 1.0f, "Touchpad Secondary Y+"));
      AddInput(new Axis(ds_gamepad.touchpadSecondary.yAxis, -1.0f, "Touchpad Secondary Y-"));
    }
    else if ([gamepad isKindOfClass:[GCXboxGamepad class]])
    {
      GCXboxGamepad* xbox_gamepad = (GCXboxGamepad*)gamepad;
      AddInput(new Button(xbox_gamepad.paddleButton1, "Paddle 1"));
      AddInput(new Button(xbox_gamepad.paddleButton2, "Paddle 2"));
      AddInput(new Button(xbox_gamepad.paddleButton3, "Paddle 3"));
      AddInput(new Button(xbox_gamepad.paddleButton4, "Paddle 4"));
    }

    GCControllerButtonInput* menu_button =
        FindPhysicalButton(controller, @[ @"Button Menu", @"Menu", @"Button Plus", @"Plus", @"+" ]);
    if (menu_button != nil)
    {
      AddInput(new Button(menu_button, "Menu"));
    }
    else
    {
      AddInput(new Button(gamepad.buttonMenu, "Menu"));
    }

    GCControllerButtonInput* options_button =
        FindPhysicalButton(controller, @[ @"Button Options", @"Options", @"Button Minus", @"Minus", @"-" ]);
    if (options_button != nil)
    {
      AddInput(new Button(options_button, "Options"));
    }
    else if (gamepad.buttonOptions != nil)
    {
      AddInput(new Button(gamepad.buttonOptions, "Options"));
    }

    if (gamepad.leftThumbstickButton != nil)
    {
      AddInput(new Button(gamepad.leftThumbstickButton, "L Stick"));
    }

    if (gamepad.rightThumbstickButton != nil)
    {
      AddInput(new Button(gamepad.rightThumbstickButton, "R Stick"));
    }
  }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  else if (controller.gamepad != nil)
  {
    // Deprecated in iOS 10, but needed for some older controllers
    GCGamepad* gamepad = controller.gamepad;
    AddInput(new Button(gamepad.buttonA, "Button A"));
    AddInput(new Button(gamepad.buttonB, "Button B"));
    AddInput(new Button(gamepad.buttonX, "Button X"));
    AddInput(new Button(gamepad.buttonY, "Button Y"));
    AddInput(new Button(gamepad.dpad.up, "D-Pad Up"));
    AddInput(new Button(gamepad.dpad.down, "D-Pad Down"));
    AddInput(new Button(gamepad.dpad.left, "D-Pad Left"));
    AddInput(new Button(gamepad.dpad.right, "D-Pad Right"));
    AddInput(new PressureSensitiveButton(gamepad.leftShoulder, "L Shoulder"));
    AddInput(new PressureSensitiveButton(gamepad.rightShoulder, "R Shoulder"));
    add_physical_button(@[ @"Button Menu", @"Menu", @"Button Plus", @"Plus", @"+" ], "Menu");
    add_physical_button(@[ @"Button Options", @"Options", @"Button Minus", @"Minus", @"-" ], "Options");
    add_flexible_physical_button(@[ @"Button Home", @"Home" ], @[ @"Home" ], "Home");
    add_flexible_physical_button(@[ @"Button Capture", @"Capture", @"Button Screenshot",
                                    @"Screenshot", @"Button Share", @"Share" ],
                                 @[ @"Capture", @"Screenshot", @"Share" ], "Capture");
    add_flexible_physical_button(@[ @"Button Capture", @"Capture", @"Button Screenshot",
                                    @"Screenshot", @"Button Share", @"Share" ],
                                 @[ @"Capture", @"Screenshot", @"Share" ], "Screenshot");
  }
#pragma clang diagnostic pop
  else if (controller.microGamepad != nil)  // Siri Remote
  {
    GCMicroGamepad* gamepad = controller.microGamepad;
    AddInput(new Button(gamepad.dpad.up, "D-Pad Up"));
    AddInput(new Button(gamepad.dpad.down, "D-Pad Down"));
    AddInput(new Button(gamepad.dpad.left, "D-Pad Left"));
    AddInput(new Button(gamepad.dpad.right, "D-Pad Right"));
    AddInput(new Button(gamepad.buttonA, "Button A"));
    AddInput(new Button(gamepad.buttonX, "Button X"));
    AddInput(new Button(gamepad.buttonMenu, "Menu"));
  }

  add_raw_physical_buttons();

  if (controller.motion != nil)
  {
    GCMotion* motion = controller.motion;

    // The DualShock 4 requires manual sensor activation
    if (motion.sensorsRequireManualActivation)
    {
      motion.sensorsActive = true;
    }
    
    AddInput(new AccelerometerAxis(motion, X, 1.0, "Accel Left"));
    AddInput(new AccelerometerAxis(motion, X, -1.0, "Accel Right"));
    AddInput(new AccelerometerAxis(motion, Y, -1.0, "Accel Forward"));
    AddInput(new AccelerometerAxis(motion, Y, 1.0, "Accel Back"));
    AddInput(new AccelerometerAxis(motion, Z, 1.0, "Accel Up"));
    AddInput(new AccelerometerAxis(motion, Z, -1.0, "Accel Down"));
    
    m_supports_accelerometer = true;
    m_supports_gyroscope = motion.hasRotationRate;

    if (m_supports_gyroscope)
    {
      AddInput(new GyroscopeAxis(motion, X, -1.0, "Gyro Pitch Up"));
      AddInput(new GyroscopeAxis(motion, X, 1.0, "Gyro Pitch Down"));
      AddInput(new GyroscopeAxis(motion, Y, 1.0, "Gyro Roll Left"));
      AddInput(new GyroscopeAxis(motion, Y, -1.0, "Gyro Roll Right"));
      AddInput(new GyroscopeAxis(motion, Z, 1.0, "Gyro Yaw Left"));
      AddInput(new GyroscopeAxis(motion, Z, -1.0, "Gyro Yaw Right"));
    }
  }
  else
  {
    m_supports_accelerometer = false;
  }

  GCDeviceHaptics* haptics = controller.haptics;
  if (haptics != nil)
  {
    CHHapticEngine* engine = [haptics createEngineWithLocality:GCHapticsLocalityDefault];
    
    AddOutput(new Motor(engine, "Rumble"));
  }
}

std::string MFiController::GetName() const
{
  NSString* vendor_name = [m_controller vendorName];
  if (vendor_name != nil)
  {
    return std::string([vendor_name UTF8String]);
  }
  else
  {
    return "Unknown Controller";
  }
}

std::string MFiController::GetSource() const
{
  return "MFi";
}

bool MFiController::SupportsAccelerometer() const
{
  return m_supports_accelerometer;
}

bool MFiController::SupportsGyroscope() const
{
  return m_supports_gyroscope;
}

bool MFiController::IsSameController(GCController* controller) const
{
  return m_controller == controller;
}

std::string MFiController::Button::GetName() const
{
  return m_name;
}

ControlState MFiController::Button::GetState() const
{
  return [m_input isPressed];
}

std::string MFiController::PressureSensitiveButton::GetName() const
{
  return m_name;
}

ControlState MFiController::PressureSensitiveButton::GetState() const
{
  return [m_input value];
}

std::string MFiController::Axis::GetName() const
{
  return m_name;
}

ControlState MFiController::Axis::GetState() const
{
  return [m_input value] * m_multiplier;
}

MFiController::AccelerometerAxis::AccelerometerAxis(GCMotion* motion, MotionPlane plane,
                                                    const double multiplier, const std::string name)
    : m_motion(motion), m_plane(plane), m_name(name)
{
  if (plane == X || plane == Y)
  {
    m_multiplier = -1.0;
  }
  else  // Z
  {
    m_multiplier = 1.0;
  }

  m_multiplier *= multiplier;
}

std::string MFiController::AccelerometerAxis::GetName() const
{
  return m_name;
}

ControlState MFiController::AccelerometerAxis::GetState() const
{
  // The DualShock 4 only returns combined gravity + acceleration.
  if ([m_motion hasGravityAndUserAcceleration])
  {
    GCAcceleration totalAcceleration = [m_motion acceleration];
    
    switch (m_plane)
    {
    case X:
      return totalAcceleration.x * m_multiplier;
    case Y:
      return totalAcceleration.y * m_multiplier;
    case Z:
      return totalAcceleration.z * m_multiplier;
    }
  }
  
  GCAcceleration acceleration = [m_motion userAcceleration];
  GCAcceleration gravity = [m_motion gravity];

  switch (m_plane)
  {
  case X:
    return acceleration.x * gravity.x * m_multiplier;
  case Y:
    return acceleration.y * gravity.y * m_multiplier;
  case Z:
    return acceleration.z * gravity.z * m_multiplier;
  }
}

MFiController::GyroscopeAxis::GyroscopeAxis(GCMotion* motion, MotionPlane plane,
                                         const double multiplier, const std::string name)
    : m_motion(motion), m_plane(plane), m_name(name)
{
  if (plane == X || plane == Y)
  {
    m_multiplier = -1.0;
  }
  else  // Z
  {
    m_multiplier = 1.0;
  }

  m_multiplier *= multiplier;
}

std::string MFiController::GyroscopeAxis::GetName() const
{
  return m_name;
}

ControlState MFiController::GyroscopeAxis::GetState() const
{
  switch (m_plane)
  {
  case X:
    return [m_motion rotationRate].x * m_multiplier;
  case Y:
    return [m_motion rotationRate].y * m_multiplier;
  case Z:
    return [m_motion rotationRate].z * m_multiplier;
  }
}
}  // namespace ciface::iOS
