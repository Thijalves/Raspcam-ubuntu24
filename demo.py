from picamera2 import Picamera2
import cv2
import numpy as np

# --- Setup camera ---
picam2 = Picamera2()
config = picam2.create_still_configuration(main={"size": (1920, 1080)})
picam2.configure(config)
picam2.start()

# --- Capture frame ---
frame = picam2.capture_array()          # RGB numpy array
picam2.stop()

# picamera2 gives RGB, OpenCV works in BGR
frame_bgr = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)

# --- Processing pipeline ---
gray     = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
blurred  = cv2.GaussianBlur(gray, (5, 5), 0)       # reduce noise before edge detection
edges    = cv2.Canny(blurred, threshold1=50, threshold2=150)

# Optional: overlay edges in green on the original image
overlay = frame_bgr.copy()
overlay[edges > 0] = (0, 255, 0)

# --- Save results ---
cv2.imwrite("original.jpg", frame_bgr)
cv2.imwrite("gray.jpg", gray)
cv2.imwrite("edges.jpg", edges)
cv2.imwrite("overlay.jpg", overlay)

print("Done! Saved: original.jpg, gray.jpg, edges.jpg, overlay.jpg")