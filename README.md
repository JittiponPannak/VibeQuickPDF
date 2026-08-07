
# VibeQuickPDF

แอป Flutter ขนาดเล็กและรวดเร็วสำหรับแปลงรูปภาพเป็นไฟล์ PDF

## รูปภาพตัวอย่าง

หน้าหลัก (ว่างปล่าว)          |  หน้าสร้างไฟล์ PDF
:-------------------------:|:-------------------------:
![Main Screen](/asset/1.1.0_main_screen.png)  | ![Create Screen](/asset/1.1.0_create_screen.png)

## คุณสมบัติ
- การแปลงภาพเป็น PDF อย่างรวดเร็ว
- ปุ่มส่งออกด่วน (Quick Export) สร้างและแชร์ PDF ทันทีโดยไม่บันทึกลงระบบ
- ตรวจสอบความสำเร็จของการแชร์ และมีระบบแจ้งเตือนให้ลองใหม่หากแชร์ไม่สำเร็จ
- เลือกรองรับการรับรูปภาพที่แชร์มาจากแอปอื่น
- เลือกรูปภาพจากที่เก็บข้อมูลหรือกล้อง
- จัดลำดับหน้าก่อนส่งออก
- แชร์ หรือบันทึกไฟล์ PDF ที่สร้างขึ้น

## ความต้องการระบบ
- Flutter (stable channel)
- SDK ของแพลตฟอร์มสำหรับ Android และ iOS (เมื่อสร้างแอปสำหรับอุปกรณ์จริง)

## เริ่มต้นอย่างรวดเร็ว

โคลนรีโพ และติดตั้ง dependencies:

```bash
git clone https://github.com/JittiponPannak/VibeQuickPDF.git
cd VibeQuickPDF
flutter pub get
```

รันบนอุปกรณ์ที่เชื่อมต่อหรือตัวจำลอง:

```bash
flutter run
```

สร้างไฟล์ APK สำหรับ Android (release):

```bash
flutter build apk --release
```

## โครงสร้างโปรเจกต์

- [lib/main.dart](lib/main.dart): จุดเริ่มต้นของแอป
- [lib/screens/home_screen.dart](lib/screens/home_screen.dart): UI หน้าแรกและการไหลหลัก
- [lib/screens/conversion_screen.dart](lib/screens/conversion_screen.dart): หน้าเลือกภาพและแปลงเป็น PDF
- [lib/services/file_service.dart](lib/services/file_service.dart): ฟังก์ชันช่วยจัดการไฟล์และการเข้าถึงที่เก็บ
- [lib/services/pdf_service.dart](lib/services/pdf_service.dart): ตรรกะการสร้าง PDF
- [lib/models/pdf_file.dart](lib/models/pdf_file.dart): โมเดลข้อมูลเมตาของ PDF
