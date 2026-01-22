const express = require("express");
const multer = require("multer");
const path = require("path");
const fs = require("fs");

const router = express.Router();

// Speichert erstmal lokal. Später: S3 / Cloudinary / Supabase Storage
const uploadDir = path.join(__dirname, "..", "uploads");
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || "");
    cb(null, `${Date.now()}-${Math.random().toString(16).slice(2)}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
});

router.post("/profile-photo", upload.single("file"), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "No file uploaded" });
  }

  // URL, unter der die Datei erreichbar ist
  const url = `${req.protocol}://${req.get("host")}/uploads/${req.file.filename}`;
  return res.json({ url });
});

// Employer company logo
router.post("/company-logo", upload.single("file"), (req, res) => {
  if (!req.file) return res.status(400).json({ error: "No file uploaded" });

  const url = `${req.protocol}://${req.get("host")}/uploads/${req.file.filename}`;
  return res.json({ url });
});

module.exports = router;