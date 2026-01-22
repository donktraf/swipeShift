// src/mail/transporter.js
const nodemailer = require("nodemailer");

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 1025),
  secure: false,
});

module.exports = { transporter };