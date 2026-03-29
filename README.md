# Vytal

**Vytal** is a simple mobile health triage concept that uses a phone camera to estimate basic vitals, collects symptoms through a guided conversation, and turns everything into a plain-language health summary the user can share with a clinician.

## Core Idea

A phone camera can measure heartbeat-related signals through tiny color changes in the face caused by blood flow. Using the **Presage SmartSpectra SDK**, Vytal captures remote photoplethysmography (rPPG) data without any wearable hardware.

## How It Works

### 1. Biometric Capture
The user holds up their phone, faces the camera, and completes a short scan.

The SDK analyzes facial color micro-fluctuations caused by blood flow and estimates:

- Heart Rate (HR)
- Heart Rate Variability (HRV)
- Respiratory Rate (RR)

No wearable. No oximeter. Just a phone.

### 2. Symptom Collection
After the scan, **Claude API** runs a guided symptom intake instead of asking for a free-text response.

It uses structured, branching questions such as:

- Where is the pain?
- Does it get worse when you breathe deeply?
- How long has this been happening?

This makes the flow easier to use for people who are not familiar with medical forms.

### 3. LangGraph Pipeline
Vital signs and symptoms are processed through a 4-agent pipeline:

| Agent | Purpose |
|---|---|
| **Vitals Interpreter** | Reviews HR, HRV, and RR against clinical baselines |
| **Symptom Assessor** | Identifies symptom patterns and possible clinical concerns |
| **Triage Agent** | Combines vitals + symptoms and assigns an urgency level |
| **Explainer Agent** | Rewrites the result in plain language at a simple reading level |

### 4. Output
The app generates a shareable health summary that can be shown to a doctor.

It includes:

- Vitals snapshot
- Reported symptoms
- Triage classification
- Plain-language explanation
- Timestamp and session ID

## User Flow

1. Open the app and select a language  
2. Hold the phone at arm’s length and look at the camera  
3. Complete a 30-second face scan  
4. View estimated vitals on screen  
5. Answer 5–8 guided symptom questions  
6. Wait for the LangGraph pipeline to process the results  
7. Receive a triage recommendation  
8. Save, screenshot, print, or share the health summary

## Example Triage Output

**Yellow — Schedule a visit within 48 hours**

The app also explains why the result was given and what symptoms would mean the situation is getting worse.

## Why It Matters

Vytal is designed to make basic health screening:

- easier to access
- easier to understand
- easier to share with clinicians
- possible without special hardware

## Tech Stack

- **Custom CD Pipeline** for face-based vitals estimation
- **Claude API** for guided symptom intake
- **LangGraph** for agent orchestration
- **Mobile app frontend** for capture and summary display

## Notes

This project is intended for triage support and health communication, not as a replacement for professional medical care.
