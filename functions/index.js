const functions = require("firebase-functions");
const PDFDocument = require("pdfkit");

exports.generateReceiptPdf = functions.https.onRequest((req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  try {
    const data =
      typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
    const { image } = data;
    if (!image) {
      res.status(400).send("Missing image field");
      return;
    }

    const imageBuffer = Buffer.from(image, "base64");

    const doc = new PDFDocument({ size: "A4", margin: 0 });
    res.setHeader("Content-Type", "application/pdf");
    res.setHeader("Content-Disposition", "attachment; filename=receipt.pdf");
    doc.pipe(res);

    doc.image(imageBuffer, 0, 0, { width: 595, height: 842 });

    doc.end();
  } catch (e) {
    res.status(500).send("PDF generation failed: " + e.message);
  }
});

exports.generateContractPdf = functions.https.onRequest((req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  let data = {};

  try {
    if (req.rawBody) {
      data = JSON.parse(req.rawBody.toString());
    } else if (typeof req.body === "string") {
      data = JSON.parse(req.body);
    } else {
      data = req.body || {};
    }
  } catch (e) {
    console.log("JSON parse error:", e);
  }

  const doc = new PDFDocument({
    size: "A4",
    margin: 40,
  });

  const chunks = [];

  // Collect all bytes first, then send one complete PDF response.
  doc.on("data", (chunk) => chunks.push(chunk));

  doc.on("end", () => {
    const result = Buffer.concat(chunks);
    res.setHeader("Content-Type", "application/pdf");
    res.setHeader("Content-Disposition", "attachment; filename=contract.pdf");
    res.setHeader("Content-Length", result.length);
    res.end(result);
  });

  doc.fontSize(18).text("Contract Paper", { align: "center" });
  doc.moveDown();

  doc.moveTo(40, doc.y).lineTo(550, doc.y).stroke();
  doc.moveDown();

  doc.fontSize(12);
  doc.text("Name: " + (data.name || ""));
  doc.text("Mobile: " + (data.mobile || ""));
  doc.text("Address: " + (data.address || ""));

  doc.moveDown();

  doc.text("Description:");
  doc.text(data.description || "", { width: 500 });

  doc.moveDown();

  doc.fontSize(14).text("Grand Total: " + (data.total || "0"), {
    align: "right",
  });

  doc.end();
});
