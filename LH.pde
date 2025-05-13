import processing.net.*;
import java.util.Calendar;
import java.io.File;
import java.io.FileWriter;
import java.io.BufferedWriter;

String currentScreen = "login";
String errorMessage = "";

Button loginButton;
Button[][] roomButtons = new Button[4][4];
TextField[][] userFields = new TextField[4][4];

TextField usernameField;
TextField passwordField;
Checkbox showPasswordCheckbox;

boolean showErrorPopup = false;

PImage loginBackground;
PImage monitorBackground;

boolean[][] isRoomOccupied = new boolean[4][4];
boolean[][] areLightsOn = new boolean[4][4];
TextField[][] roomUserFields = new TextField[4][4];
Button[][] roomSwitchButtons = new Button[4][4];
Button[][] lightSwitchButtons = new Button[4][4];
Button[][] resetRoomButtons = new Button[4][4];

Button hallwayLightsButton;
Button resetAllButton;
Button activityLogButton;

boolean hallwayLightsOn = false;

int cursorBlinkCounter = 0;
boolean showCursor = true;

int prevWidth, prevHeight;

boolean showActivityLog = false;
Button printLogButton;
ArrayList<String[]> activityLog = new ArrayList<String[]>();

// Scroll variables for activity log
int logScrollOffset = 0;
int visibleLogEntries = 16;
int maxLogEntries = 1000;

// CSV export variables
boolean showCsvStatus = false;
int csvStatusFrame = 0;
boolean mousePressedPrevious = false;

// Network communication variables
Client espClient;
String espIP = "192.168.93.19"; // Change to your ESP32's IP
int espPort = 8888;
boolean connectedToESP = false;
long lastConnectionAttempt = 0;
long connectionInterval = 5000; // Try to reconnect every 5 seconds

// Temperature monitoring
float room101Temperature = 0.0;

void setup() {
  size(1366, 768);
  surface.setResizable(true);

  java.awt.Dimension screenSize = java.awt.Toolkit.getDefaultToolkit().getScreenSize();
  int windowX = (screenSize.width - width) / 2;
  int windowY = (screenSize.height - height) / 2;
  surface.setLocation(windowX, windowY);

  loginBackground = loadImage("PUP-CITE.jpg");
  loginBackground.resize(width, height);

  monitorBackground = loadImage("PUP-F2F.jpg");
  monitorBackground.resize(width, height);

  prevWidth = width;
  prevHeight = height;

  usernameField = new TextField(0, 0, 200, 30, false);
  passwordField = new TextField(0, 0, 200, 30, true);
  loginButton = new Button("Login", 0, 0, 80, 30, color(128, 0, 0));
  showPasswordCheckbox = new Checkbox("Show Password", 0, 0, 15);

  for (int floor = 0; floor < 4; floor++) {
    for (int room = 0; room < 4; room++) {
      roomUserFields[floor][room] = new TextField(0, 0, 200, 30, false);
      roomSwitchButtons[floor][room] = new Button("VACANT", 0, 0, 100, 20, color(0, 128, 255));
      lightSwitchButtons[floor][room] = new Button("LIGHTS", 0, 0, 100, 20, color(0, 255, 0));
      resetRoomButtons[floor][room] = new Button("RESET", 0, 0, 80, 20, color(220, 0, 0));
    }
  }
  
  hallwayLightsButton = new Button("HALLWAY LIGHTS: OFF", 0, 0, 200, 40, color(100, 100, 100));
  resetAllButton = new Button("RESET ALL", 0, 0, 150, 40, color(220, 0, 0));
  activityLogButton = new Button("ACTIVITY LOG", 0, 0, 150, 40, color(0, 100, 200));
  
  printLogButton = new Button("PRINT", 0, 0, 80, 30, color(0, 150, 0));
  
  // Initialize ESP32 connection
  setupESPCommunication();
}

void setupESPCommunication() {
  try {
    espClient = new Client(this, espIP, espPort);
    if (espClient.active()) {
      connectedToESP = true;
      println("Connected to ESP32");
      addToActivityLog("Connected to ESP32 at " + espIP);
    } else {
      connectedToESP = false;
      println("Failed to connect to ESP32");
      addToActivityLog("Failed to connect to ESP32");
    }
  } catch (Exception e) {
    println("Error connecting to ESP32: " + e.getMessage());
    connectedToESP = false;
    addToActivityLog("Error connecting to ESP32: " + e.getMessage());
  }
  lastConnectionAttempt = millis();
}

void draw() {
  if (width != prevWidth || height != prevHeight) {
    loginBackground.resize(width, height);
    monitorBackground.resize(width, height);
    prevWidth = width;
    prevHeight = height;
  }

  // Check ESP32 connection status
  checkESPConnection();

  background(currentScreen.equals("login") ? loginBackground : monitorBackground);

  fill(128, 0, 0);
  noStroke();
  rect(0, 0, width, 60);
  fill(255);
  textAlign(LEFT, CENTER);
  textSize(28);
  text("Smart Room Monitoring", 30, 30);

  // Display connection status
  fill(connectedToESP ? color(0, 255, 0) : color(255, 0, 0));
  ellipse(width - 30, 30, 20, 20);
  fill(255);
  textAlign(RIGHT, CENTER);
  textSize(12);
  text("", width - 40, 30);

  if (currentScreen.equals("login")) {
    drawLoginScreen();
  } else {
    drawMonitorScreen();
    if (showActivityLog) {
      drawActivityLog();
    }
  }

  if (frameCount % 30 == 0) showCursor = !showCursor;
  
  if (showCsvStatus) {
    fill(0, 200, 0, 200);
    rect(width/2 - 150, height - 40, 300, 30, 5);
    fill(255);
    textAlign(CENTER, CENTER);
    textSize(16);
    text("CSV file generated successfully!", width/2, height - 25);
    
    if (frameCount - csvStatusFrame > 120) {
      showCsvStatus = false;
    }
  }
  
  mousePressedPrevious = mousePressed;
}

void checkESPConnection() {
  if (!connectedToESP && millis() - lastConnectionAttempt > connectionInterval) {
    setupESPCommunication();
  }
  
  // Check for incoming messages from ESP32
  if (connectedToESP && espClient.available() > 0) {
    String message = espClient.readStringUntil('\n');
    if (message != null) {
      message = message.trim();
      handleESPCommand(message);
    }
  }
}

void handleESPCommand(String command) {
  println("Received from ESP32: " + command);
  addToActivityLog("ESP32: " + command);
  
  if (command.startsWith("RESET:")) {
    String[] parts = command.split(":");
    if (parts.length == 3) {
      int floor = Integer.parseInt(parts[1]) - 1;
      int room = Integer.parseInt(parts[2]) - 1;
      
      if (floor >= 0 && floor < 4 && room >= 0 && room < 4) {
        isRoomOccupied[floor][room] = false;
        areLightsOn[floor][room] = false;
        roomUserFields[floor][room].text = "";
        
        String roomNum = (floor + 1) + String.format("%02d", room + 1);
        addToActivityLog("System reset Room " + roomNum + " (from ESP32)");
      }
    }
  }
  else if (command.startsWith("TEMP:")) {
    try {
      room101Temperature = Float.parseFloat(command.substring(5));
      println("Room 101 Temperature: " + room101Temperature + "°C");
    } catch (NumberFormatException e) {
      println("Error parsing temperature: " + e.getMessage());
    }
  }
}

void sendToESP(String command) {
  if (connectedToESP) {
    try {
      espClient.write(command + "\n");
      println("Sent to ESP32: " + command);
    } catch (Exception e) {
      println("Error sending to ESP32: " + e.getMessage());
      connectedToESP = false;
      addToActivityLog("Error sending to ESP32: " + e.getMessage());
    }
  } else {
    println("Not connected to ESP32 - cannot send: " + command);
    addToActivityLog("Failed to send to ESP32: " + command);
  }
}

void drawLoginScreen() {
  fill(0);
  textAlign(CENTER, CENTER);
  textSize(64);
  text("LockHub", width / 7, height / 2 - 180);
  textSize(24);
  text("Central Command System", width / 7, height / 3);

  float boxX = width / 20 + 5;
  float boxWidth = 250;
  float boxHeight = 240;

  fill(0, 0, 0, 80);
  noStroke();
  rect(boxX - 10, height / 2 - 70 - 10, boxWidth, boxHeight, 30);

  fill(255);
  stroke(180);
  strokeWeight(1);
  rect(boxX, height / 2 - 70, boxWidth, boxHeight, 20);

  fill(0);
  textAlign(CENTER, CENTER);
  textSize(16);

  text("User", boxX + boxWidth / 2, height / 2 - 40);
  usernameField.x = boxX + boxWidth / 2 - usernameField.w / 2;
  usernameField.y = height / 2 - 25;
  usernameField.display();

  text("Password", boxX + boxWidth / 2.7, height / 2 + 25);
  passwordField.x = boxX + boxWidth / 2 - passwordField.w / 2;
  passwordField.y = height / 2 + 35;
  passwordField.display();

  showPasswordCheckbox.x = boxX + 25;
  showPasswordCheckbox.y = height / 2 + 80;
  showPasswordCheckbox.display();

  loginButton.x = boxX + boxWidth / 2 - loginButton.w / 2;
  loginButton.y = height / 2 + 120;
  loginButton.display();

  if (showErrorPopup) {
    drawErrorPopup();
  }
}

void drawMonitorScreen() {
  background(monitorBackground);
  fill(0, 80);
  rect(0, 0, width, height);

  textAlign(CENTER, CENTER);
  textSize(32);
  fill(255);
  text("Room Monitoring", width / 2, 30);

  String[] floors = { "1st Floor", "2nd Floor", "3rd Floor", "4th Floor" };
  float colWidth = width * 0.187;
  float startX = width * 0.05;
  float topMargin = 80;
  float colHeight = height * 0.75;

  for (int floor = 0; floor < 4; floor++) {
    float x = startX + floor * colWidth;
    stroke(255);
    fill(255, 30);
    rect(x, topMargin, colWidth - 10, colHeight, 15);
    fill(255);
    textSize(18);
    text(floors[floor], x + (colWidth / 2) - 5, topMargin - 20);

    for (int room = 0; room < 4; room++) {
      float roomPanelX = x + 10;
      float roomPanelY = topMargin + 40 + room * (colHeight / 4);

      fill(255, 255, 255, 100);
      noStroke();
      rect(roomPanelX - 5, roomPanelY - 35, 235, 120, 10);

      fill(0);
      textSize(16);
      textAlign(LEFT, CENTER);
      
      // Special display for ROOM 101 with temperature
      if (floor == 0 && room == 0) {
        text("ROOM 101               (" + nf(room101Temperature, 0, 1) + "°C)", roomPanelX + 60, roomPanelY - 20);
      } else {
        text("ROOM " + (floor + 1) + String.format("%02d", room + 1), roomPanelX + 77, roomPanelY - 20);
      }

      roomSwitchButtons[floor][room].label = isRoomOccupied[floor][room] ? "OCCUPIED" : "VACANT";
      roomSwitchButtons[floor][room].baseColor = isRoomOccupied[floor][room] ? color(255, 0, 0) : color(0, 255, 0);
      roomSwitchButtons[floor][room].x = roomPanelX + 5;
      roomSwitchButtons[floor][room].y = roomPanelY + 1;
      roomSwitchButtons[floor][room].display();

      lightSwitchButtons[floor][room].label = areLightsOn[floor][room] ? "ON" : "OFF";
      lightSwitchButtons[floor][room].baseColor = areLightsOn[floor][room] ? color(255, 255, 0) : color(128, 128, 128);
      lightSwitchButtons[floor][room].x = roomPanelX + 120;
      lightSwitchButtons[floor][room].y = roomPanelY + 1;
      lightSwitchButtons[floor][room].display();

      roomUserFields[floor][room].x = roomPanelX + 10;
      roomUserFields[floor][room].y = roomPanelY + 25;
      roomUserFields[floor][room].display();

      resetRoomButtons[floor][room].x = roomPanelX + 70;
      resetRoomButtons[floor][room].y = roomPanelY + 60;
      resetRoomButtons[floor][room].display();
    }
  }
  float fifthColX = startX + 4 * colWidth;
  noStroke();
  fill(255, 0);
  rect(fifthColX, topMargin, colWidth - 10, colHeight + 37, 15);
  fill(255);

  float occupiedRowY = topMargin + 40;
  fill(255, 255, 255, 100);
  noStroke();
  rect(fifthColX + 5, occupiedRowY - 35, colWidth - 20, 275, 10);

  fill(0);
  textSize(16);
  textAlign(CENTER);
  text("OCCUPIED ROOMS", fifthColX + 10 + (colWidth - 20) / 2, occupiedRowY - 20);

  int occupiedRoomCount = 0;
  int maxRowsPerCol = 8;
  int colSpacing = 100;
  int rowHeight = 30;

  for (int floor = 0; floor < 4; floor++) {
    for (int room = 0; room < 4; room++) {
      if (isRoomOccupied[floor][room]) {
        int colIndex = occupiedRoomCount / maxRowsPerCol;
        int rowIndex = occupiedRoomCount % maxRowsPerCol;

        float x = fifthColX + 30 + colIndex * colSpacing;
        float y = occupiedRowY + rowIndex * rowHeight;

        textAlign(LEFT);
        text("Room " + (floor + 1) + String.format("%02d", room + 1), x, y);

        occupiedRoomCount++;
      }
    }
  }

  float activeLightsRowY = topMargin + 200;
  fill(255, 255, 255, 100);
  noStroke();
  rect(fifthColX + 5, activeLightsRowY + 85, colWidth - 20, 270, 10);

  fill(0);
  textSize(16);
  textAlign(CENTER);
  text("ACTIVE LIGHTS", fifthColX + 10 + (colWidth - 30) / 2, activeLightsRowY + 100);

  int activeLightsCount = 0;
  int maxRowsPerColLights = 8;
  int colSpacingLights = 100;
  int rowHeightLights = 30;

  for (int floor = 0; floor < 4; floor++) {
    for (int room = 0; room < 4; room++) {
      if (areLightsOn[floor][room]) {
        int colIndex = activeLightsCount / maxRowsPerColLights;
        int rowIndex = activeLightsCount % maxRowsPerColLights;

        float x = fifthColX + 30 + colIndex * colSpacingLights;
        float y = activeLightsRowY + 120 + rowIndex * rowHeightLights;

        textAlign(LEFT);
        text("Room " + (floor + 1) + String.format("%02d", room + 1), x, y);

        activeLightsCount++;
      }
    }
  }

  float buttonY = height - 60;
  float buttonSpacing = 20;
  float totalButtonWidth = hallwayLightsButton.w + resetAllButton.w + activityLogButton.w + 2 * buttonSpacing;
  float startButtonX = (width - totalButtonWidth) / 2;
  
  hallwayLightsButton.x = startButtonX + 120;
  hallwayLightsButton.y = buttonY;
  hallwayLightsButton.label = "HALLWAY LIGHTS: " + (hallwayLightsOn ? "ON" : "OFF");
  hallwayLightsButton.baseColor = hallwayLightsOn ? color(255, 255, 0) : color(100, 100, 100);
  hallwayLightsButton.display();
  
  resetAllButton.x = startButtonX + hallwayLightsButton.w + 7 * buttonSpacing;
  resetAllButton.y = buttonY;
  resetAllButton.display();
  
  activityLogButton.x = startButtonX + hallwayLightsButton.w + resetAllButton.w + 8 * buttonSpacing;
  activityLogButton.y = buttonY;
  activityLogButton.display();

  textAlign(LEFT, CENTER);
  textSize(20);
  fill(0);
  Calendar now = Calendar.getInstance();
  String[] days = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" };
  String currentDay = days[now.get(Calendar.DAY_OF_WEEK) - 1];

  int hour24 = now.get(Calendar.HOUR_OF_DAY);
  int hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  String meridian = hour24 >= 12 ? "PM" : "AM";

  String timeString = String.format("%02d:%02d %s", hour12, now.get(Calendar.MINUTE), meridian);
  String dateString = String.format("%02d/%02d/%04d", 
      now.get(Calendar.MONTH) + 1, 
      now.get(Calendar.DAY_OF_MONTH), 
      now.get(Calendar.YEAR));

  text("DAY: " + currentDay + "    DATE: " + dateString, width * 0.05f, height - 40);
  text("TIME: " + timeString, width * 0.27f, height - 40);
}

void drawActivityLog() {
  float popupWidth = width * 0.8;
  float popupHeight = height * 0.85;
  float popupX = (width - popupWidth) / 2;
  float popupY = (height - popupHeight) / 1.1;
  
  fill(240);
  stroke(0);
  strokeWeight(2);
  rect(popupX, popupY, popupWidth, popupHeight, 10);
  
  fill(0);
  textAlign(CENTER, CENTER);
  textSize(24);
  text("ACTIVITY LOG", popupX + popupWidth/2, popupY + 30);
  
  fill(200);
  rect(popupX + 20, popupY + 60, popupWidth - 40, 40);
  
  fill(0);
  textAlign(LEFT, CENTER);
  textSize(16);
  text("USER", popupX + 30, popupY + 80);
  text("ROOM NO.", popupX + 150, popupY + 80);
  text("ROOM STATUS", popupX + 250, popupY + 80);
  text("LIGHTS", popupX + 380, popupY + 80);
  text("DATE", popupX + 480, popupY + 80);
  text("TIME", popupX + 630, popupY + 80);
  
  stroke(150);
  line(popupX + 130, popupY + 60, popupX + 130, popupY + popupHeight - 13);
  line(popupX + 230, popupY + 60, popupX + 230, popupY + popupHeight - 13);
  line(popupX + 370, popupY + 60, popupX + 370, popupY + popupHeight - 13);
  line(popupX + 470, popupY + 60, popupX + 470, popupY + popupHeight - 13);
  line(popupX + 620, popupY + 60, popupX + 620, popupY + popupHeight - 13);
  
  stroke(200);
  for (int i = 0; i < 17; i++) {
    float y = popupY + 100 + i * 30;
    line(popupX + 20, y, popupX + popupWidth - 20, y);
  }
  
  textAlign(LEFT, CENTER);
  textSize(14);
  
  int startIndex = min(logScrollOffset, max(0, activityLog.size() - visibleLogEntries));
  int endIndex = min(startIndex + visibleLogEntries, activityLog.size());
  
  for (int i = startIndex; i < endIndex; i++) {
    float y = popupY + 80 + (i - startIndex) * 30 + 30;
    String[] entry = activityLog.get(i);
    text(entry[0], popupX + 30, y);
    text(entry[1], popupX + 150, y);
    text(entry[5], popupX + 250, y);
    text(entry[2], popupX + 380, y);
    text(entry[3], popupX + 480, y);
    text(entry[4], popupX + 630, y);
  }
  
  if (activityLog.size() > visibleLogEntries) {
    Button scrollUp = new Button("↑", popupX + popupWidth - 30, popupY + 150, 20, 150, color(200));
    Button scrollDown = new Button("↓", popupX + popupWidth - 30, popupY + popupHeight - 250, 20, 150, color(200));
    
    scrollUp.display();
    scrollDown.display();
    
    if (scrollUp.isHovered() && mousePressed) {
      logScrollOffset = max(1, logScrollOffset - 1);
    }
    if (scrollDown.isHovered() && mousePressed) {
      logScrollOffset = min(activityLog.size() - visibleLogEntries, logScrollOffset + 1);
    }
  }
  
  printLogButton.x = popupX + popupWidth - 100;
  printLogButton.y = popupY + popupHeight - 40;
  printLogButton.display();
  
  if (printLogButton.isHovered() && mousePressed) {
    fill(0, 150, 0, 100);
    rect(printLogButton.x, printLogButton.y, printLogButton.w, printLogButton.h, 5);
    
    if (!mousePressedPrevious) {
      exportActivityLogToCSV();
    }
  }
  
  Button closeButton = new Button("CLOSE", popupX + popupWidth - 180, popupY + popupHeight - 40, 70, 30, color(220, 0, 0));
  closeButton.display();
  
  if (closeButton.isHovered() && mousePressed) {
    showActivityLog = false;
    logScrollOffset = 0;
  }
}

void exportActivityLogToCSV() {
  try {
    Calendar now = Calendar.getInstance();
    String timestamp = String.format("%04d%02d%02d_%02d%02d%02d", 
        now.get(Calendar.YEAR), 
        now.get(Calendar.MONTH) + 1, 
        now.get(Calendar.DAY_OF_MONTH),
        now.get(Calendar.HOUR_OF_DAY),
        now.get(Calendar.MINUTE),
        now.get(Calendar.SECOND));
    
    String filename = "activity_log_" + timestamp + ".csv";
    String filepath = sketchPath(filename);
    
    BufferedWriter writer = new BufferedWriter(new FileWriter(filepath));
    
    writer.write("USER,ROOM NO.,ROOM STATUS,LIGHTS,DATE,TIME");
    writer.newLine();
    
    for (String[] entry : activityLog) {
      writer.write(
        escapeCSV(entry[0]) + "," +
        escapeCSV(entry[1]) + "," +
        escapeCSV(entry[5]) + "," +
        escapeCSV(entry[2]) + "," +
        escapeCSV(entry[3]) + "," +
        escapeCSV(entry[4])
      );
      writer.newLine();
    }
    
    writer.close();
    
    println("CSV file successfully generated: " + filepath);
    
    showCsvStatus = true;
    csvStatusFrame = frameCount;
    
    showErrorPopup("CSV exported to:\n" + filename);
  } 
  catch (Exception e) {
    println("Error exporting CSV: " + e.getMessage());
    showErrorPopup("Error exporting CSV:\n" + e.getMessage());
  }
}

String escapeCSV(String value) {
  if (value == null) {
    return "";
  }
  if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
    return "\"" + value.replace("\"", "\"\"") + "\"";
  }
  return value;
}

void addToActivityLog(String message) {
  Calendar now = Calendar.getInstance();
  String timestamp = String.format("%02d:%02d", 
      now.get(Calendar.HOUR_OF_DAY), 
      now.get(Calendar.MINUTE));
  String date = String.format("%02d/%02d/%04d", 
      now.get(Calendar.MONTH) + 1, 
      now.get(Calendar.DAY_OF_MONTH), 
      now.get(Calendar.YEAR));
  
  String user = "System";
  String room = "";
  String lights = "";
  String roomStatus = "";
  
  if (message.contains("occupied Room") || message.contains("vacated Room")) {
    String action = message.contains("occupied") ? "occupied" : "vacated";
    int roomIndex = message.indexOf("Room");
    if (roomIndex > 0) {
      user = message.substring(0, message.indexOf(action + " Room")).trim();
      room = message.substring(roomIndex).trim();
      
      try {
        String roomNumStr = room.replaceAll("[^0-9]", "");
        int roomNum = Integer.parseInt(roomNumStr);
        int floor = (roomNum / 100) - 1;
        int roomOnly = (roomNum % 100) - 1;
        
        if (floor >= 0 && floor < 4 && roomOnly >= 0 && roomOnly < 4) {
          roomStatus = isRoomOccupied[floor][roomOnly] ? "OCCUPIED" : "VACANT";
        } else {
          roomStatus = "INVALID";
        }
      } catch (NumberFormatException e) {
        roomStatus = "ERROR";
      }
    }
  } 
  else if (message.contains("turned ON lights") || message.contains("turned OFF lights")) {
    String lightState = message.contains("turned ON") ? "ON" : "OFF";
    int roomIndex = message.indexOf("Room");
    if (roomIndex > 0) {
      user = message.substring(0, message.indexOf("turned " + lightState + " lights")).trim();
      room = message.substring(roomIndex).trim();
      lights = lightState;
      
      try {
        String roomNumStr = room.replaceAll("[^0-9]", "");
        int roomNum = Integer.parseInt(roomNumStr);
        int floor = (roomNum / 100) - 1;
        int roomOnly = (roomNum % 100) - 1;
        
        if (floor >= 0 && floor < 4 && roomOnly >= 0 && roomOnly < 4) {
          roomStatus = isRoomOccupied[floor][roomOnly] ? "OCCUPIED" : "VACANT";
        } else {
          roomStatus = "INVALID";
        }
      } catch (NumberFormatException e) {
        roomStatus = "ERROR";
      }
    }
  } 
  else if (message.contains("Hallway lights turned")) {
    String[] parts = message.split(" ");
    user = "System";
    room = "Hallway";
    lights = parts[3];
    roomStatus = "";
  } 
  else if (message.contains("System reset")) {
    String[] parts = message.split(" ");
    user = "System";
    if (message.contains("ALL ROOMS")) {
      room = "ALL ROOMS";
      roomStatus = "VACANT";
      lights = "OFF";
    } else {
      user = "";
      String roomNum = parts[parts.length - 1];
      room = "Room " + roomNum;
      roomStatus = "VACANT";
      lights = "OFF";
    }
  }
  else if (message.contains("ESP32:")) {
    user = "ESP32";
    room = "";
    lights = "";
    roomStatus = "";
  }
  
  String[] logEntry = {user, room, lights, date, timestamp, roomStatus};
  activityLog.add(0, logEntry);
  
  if (activityLog.size() > maxLogEntries) {
    activityLog.remove(activityLog.size() - 1);
  }
}

void drawErrorPopup() {
  float popupWidth = 250;
  float popupHeight = 250;
  float popupX = width / 7 - popupWidth / 2;
  float popupY = height / 1.97 - popupHeight / 3;

  fill(128, 0, 0); 
  stroke(0);
  strokeWeight(2);
  rect(popupX, popupY, popupWidth, popupHeight, 10);

  fill(255);
  textAlign(CENTER, CENTER);
  textSize(18);
  text(errorMessage, width / 7, height / 2 - 10);

  Button closeButton = new Button("Close", width / 7 - 50, height / 2 + 70, 100, 40, color(255));
  closeButton.display();

  if (closeButton.isHovered() && mousePressed) {
    showErrorPopup = false;
  }
}

void mousePressed() {
  if (currentScreen.equals("login")) {
    usernameField.mousePressed();
    passwordField.mousePressed();
    showPasswordCheckbox.mousePressed();

    if (usernameField.isHovered()) {
      passwordField.selected = false;
    } else if (passwordField.isHovered()) {
      usernameField.selected = false;
    }

    if (loginButton.isHovered()) {
      tryLogin();
    }
  } else if (currentScreen.equals("monitor")) {
    for (int floor = 0; floor < 4; floor++) {
      for (int room = 0; room < 4; room++) {
        roomUserFields[floor][room].mousePressed();

        if (roomSwitchButtons[floor][room].isHovered()) {
          if (!roomUserFields[floor][room].text.trim().isEmpty()) {
            boolean previousState = isRoomOccupied[floor][room];
            isRoomOccupied[floor][room] = !isRoomOccupied[floor][room];
            
            // Send command to ESP32
            String roomNum = (floor + 1) + String.format("%02d", room + 1);
            String command = "ROOM:" + roomNum + ":" + (isRoomOccupied[floor][room] ? "OCCUPIED" : "VACANT");
            sendToESP(command);
            
            if (isRoomOccupied[floor][room] && !previousState) {
              addToActivityLog(roomUserFields[floor][room].text + " occupied Room " + roomNum);
            } else if (!isRoomOccupied[floor][room] && previousState) {
              addToActivityLog(roomUserFields[floor][room].text + " vacated Room " + roomNum);
            }
          } else {
            showErrorPopup("Please enter a user name first");
          }
        }

        if (lightSwitchButtons[floor][room].isHovered()) {
          if (!roomUserFields[floor][room].text.trim().isEmpty()) {
            boolean previousState = areLightsOn[floor][room];
            areLightsOn[floor][room] = !areLightsOn[floor][room];
            
            // Send command to ESP32
            String roomNum = (floor + 1) + String.format("%02d", room + 1);
            String command = "LIGHT:" + roomNum + ":" + (areLightsOn[floor][room] ? "ON" : "OFF");
            sendToESP(command);
            
            if (areLightsOn[floor][room] && !previousState) {
              addToActivityLog(roomUserFields[floor][room].text + " turned ON lights in Room " + roomNum);
            } else if (!areLightsOn[floor][room] && previousState) {
              addToActivityLog(roomUserFields[floor][room].text + " turned OFF lights in Room " + roomNum);
            }
          } else {
            showErrorPopup("Please enter a user name first");
          }
        }

        if (resetRoomButtons[floor][room].isHovered()) {
          if (isRoomOccupied[floor][room] || areLightsOn[floor][room] || !roomUserFields[floor][room].text.isEmpty()) {
            String roomNum = (floor + 1) + String.format("%02d", room + 1);
            addToActivityLog("System reset Room " + roomNum);
            isRoomOccupied[floor][room] = false;
            areLightsOn[floor][room] = false;
            roomUserFields[floor][room].text = "";
            
            // Send reset command to ESP32
            sendToESP("RESET:" + roomNum);
          }
        }
      }
    }
    
    if (hallwayLightsButton.isHovered()) {
      boolean previousState = hallwayLightsOn;
      hallwayLightsOn = !hallwayLightsOn;
      
      if (hallwayLightsOn && !previousState) {
        addToActivityLog("Hallway lights turned ON");
      } else if (!hallwayLightsOn && previousState) {
        addToActivityLog("Hallway lights turned OFF");
      }
    }
    
    if (resetAllButton.isHovered()) {
      boolean anyRoomReset = false;
      
      for (int floor = 0; floor < 4; floor++) {
        for (int room = 0; room < 4; room++) {
          if (isRoomOccupied[floor][room] || areLightsOn[floor][room] || !roomUserFields[floor][room].text.isEmpty()) {
            anyRoomReset = true;
            isRoomOccupied[floor][room] = false;
            areLightsOn[floor][room] = false;
            roomUserFields[floor][room].text = "";
            
            // Send reset command for each room
            String roomNum = (floor + 1) + String.format("%02d", room + 1);
            sendToESP("RESET:" + roomNum);
          }
        }
      }
      
      if (anyRoomReset) {
        addToActivityLog("System reset ALL ROOMS");
      }
    }
    
    if (activityLogButton.isHovered()) {
     showActivityLog = !showActivityLog;
         }
  }
}

void showErrorPopup(String message) {
  errorMessage = message;
  showErrorPopup = true;
}

void keyPressed() {
  if (currentScreen.equals("login")) {
    if (key == TAB) {
      usernameField.selected = !usernameField.selected;
      passwordField.selected = !usernameField.selected;
    } else if (key == ENTER || key == RETURN) {
      tryLogin();
    } else {
      if (usernameField.selected) {
        usernameField.keyPressed();
      } else if (passwordField.selected) {
        passwordField.keyPressed();
      }
    }
  } else if (currentScreen.equals("monitor")) {
    for (int floor = 0; floor < 4; floor++) {
      for (int room = 0; room < 4; room++) {
        roomUserFields[floor][room].keyPressed();
      }
    }
  }
}

void tryLogin() {
  if (usernameField.text.equals("Administrator") && passwordField.text.equals("password")) {
    currentScreen = "monitor";
    showErrorPopup = false;
    addToActivityLog("System logged in");
  } else {
    showErrorPopup("Invalid username or password");
  }
}

class Button {
  String label;
  float x, y, w, h;
  color baseColor;

  Button(String label, float x, float y, float w, float h, color baseColor) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.baseColor = baseColor;
  }

  void display() {
    fill(isHovered() ? lerpColor(baseColor, color(255), 0.3) : baseColor);
    stroke(80);
    strokeWeight(1);
    rect(x, y, w, h, 5);
    fill(0);
    textAlign(CENTER, CENTER);
    textSize(16);
    text(label, x + w / 2, y + h / 2);
  }

  boolean isHovered() {
    return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
  }
}

class TextField {
  String text = "";
  float x, y, w, h;
  boolean isPassword;
  boolean selected = false;

  TextField(float x, float y, float w, float h, boolean isPassword) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.isPassword = isPassword;
  }

  void display() {
    fill(selected ? color(255, 255, 255, 150) : color(255));
    stroke(80);
    strokeWeight(1);
    rect(x, y, w, h, 5);
    fill(0);
    textAlign(LEFT, CENTER);
    textSize(16);
    String visibleText = isPassword && !showPasswordCheckbox.checked ? "*".repeat(text.length()) : text;
    text(visibleText + (selected && showCursor ? "|" : ""), x + 5, y + h / 2);
  }

  void mousePressed() {
    selected = isHovered();
  }

  boolean isHovered() {
    return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
  }

  void keyPressed() {
    if (selected) {
      if (keyCode == BACKSPACE) {
        if (text.length() > 0) {
          text = text.substring(0, text.length() - 1);
        }
      } else if (key != CODED) {
        text += key;
      }
    }
  }
}

class Checkbox {
  String label;
  float x, y, w, h, size;
  boolean checked = false;

  Checkbox(String label, float x, float y, float size) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.size = size;
    this.w = size;
    this.h = size;
  }

  void display() {
    fill(checked ? color(128, 0, 0) : color(255));
    stroke(80);
    strokeWeight(1);
    rect(x, y, w, h, 5);

    fill(0);
    textAlign(LEFT, CENTER);
    textSize(16);
    text(label, x + w + 10, y + h / 2);
  }

  void mousePressed() {
    if (isHovered()) {
      checked = !checked;
    }
  }

  boolean isHovered() {
    return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
  }
}
