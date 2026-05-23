# expense_tracker_app
A Flutter app that auto-imports bank SMS transactions, tracks daily expenses, and monitors weekly budgets with visual charts.
# 📱 Urban Expense Tracker

A Flutter app built for college students to track daily expenses, monitor weekly budgets, and automatically import transactions from bank SMS messages.

---
<img src="https://github.com/user-attachments/assets/f4affb0f-2690-4f9a-8309-f3c0d9116744" width="300" />

<img src="https://github.com/user-attachments/assets/3affc47a-73d1-4028-b61c-d10a5a5ed67f" width="300" />

---

## ✨ Features

- SMS Auto-Import — Reads bank messages from HDFC, SBI, ICICI, Axis, UPI, GPay, PhonePe, Paytm and extracts transactions automatically
- Weekly Budget — Set a budget and get alerts at 75%, 90% and 100% usage
- Spending Chart — Bar chart showing your last 7 days of spending
- Auto Categories — Sorts expenses into Food, Transport, Shopping, Entertainment, Bills and more
- Manual Entry — Add or edit expenses with category, amount and date
- Swipe to Delete — Remove any expense with a swipe
- Offline Storage — Everything saved locally on your device

---

## ⚠️ Known Issues

- SMS import works on Android only
- Merchant name detection from SMS may not always be accurate
- Some UI sections are still in progress

---

## 🛠️ Built With

- Flutter & Dart
- shared_preferences
- fl_chart
- telephony
- permission_handler
- intl

---

## ▶️ How to Run

```bash
git clone https://github.com/dhanraj9684/expense_tracker_app.git
cd urban-expense-tracker
flutter pub get
flutter run
```

SMS permission is required on Android for auto-import to work.

---

## 👨‍💻 Developer

Made by Dhanraj Sahu — Information Science Student
