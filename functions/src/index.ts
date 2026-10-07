import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { BrevoClient } from "@getbrevo/brevo";

admin.initializeApp();

// Configurar Brevo (se establece via: firebase functions:config:set brevo.key="TU_API_KEY")
const brevoKey = functions.config().brevo?.key;

let brevoClient: BrevoClient | null = null;
if (brevoKey) {
  brevoClient = new BrevoClient({ apiKey: brevoKey });
}

/**
 * Envía reporte de caja por email usando Brevo
 * 
 * Payload:
 * {
 *   pdfBase64: string,      // PDF en base64
 *   fileName: string,       // Nombre archivo
 *   toEmail: string,        // Destinatario
 *   subject?: string,       // Asunto opcional
 *   body?: string,          // Cuerpo opcional
 *   shiftData?: object      // Datos turno para template
 * }
 */
export const sendReportEmail = functions.https.onCall(
  async (request: any) => {
    const data = request.data as {
      pdfBase64: string;
      fileName: string;
      toEmail: string;
      subject?: string;
      body?: string;
      shiftData?: Record<string, unknown>;
    };

    // Validaciones
    if (!data.pdfBase64 || !data.fileName || !data.toEmail) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Faltan campos: pdfBase64, fileName, toEmail"
      );
    }

    if (!brevoClient) {
      functions.logger.error("Brevo API key no configurada");
      throw new functions.https.HttpsError(
        "internal",
        "Servicio email no configurado"
      );
    }

    try {
      // Template HTML con datos del turno
      let htmlBody = data.body || "Adjunto reporte de caja.";
      
      if (data.shiftData) {
        const d = data.shiftData;
        const isClosing = d.cashSales !== undefined;
        htmlBody = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #2c3e50;">📊 ${isClosing ? "Reporte de Cierre" : "Reporte de Apertura"} de Caja</h2>
            <p><strong>Cajero:</strong> ${d.cashierName || "N/A"}</p>
            <p><strong>Fecha:</strong> ${new Date().toLocaleString("es-ES")}</p>
            <hr style="border: 1px solid #eee;">
            <p><strong>Base inicial:</strong> $${Number(d.openingBalance || 0).toFixed(2)}</p>
            ${isClosing ? `
            <p><strong>Ventas efectivo:</strong> $${Number(d.cashSales || 0).toFixed(2)}</p>
            <p><strong>Ventas datáfono:</strong> $${Number(d.cardSales || 0).toFixed(2)}</p>
            <p><strong>Ventas transferencias:</strong> $${Number(d.transferSales || 0).toFixed(2)}</p>
            <hr style="border: 1px solid #eee;">
            <p><strong>Esperado en caja:</strong> $${Number(d.expectedCash || 0).toFixed(2)}</p>
            <p><strong>Reportado físico:</strong> $${Number(d.reportedCash || 0).toFixed(2)}</p>
            <p><strong>Diferencia:</strong> $${Number(d.difference || 0).toFixed(2)}</p>
            ` : ""}
            <hr style="border: 1px solid #eee;">
            <p style="color: #7f8c8d;">Adjunto PDF con el detalle completo.</p>
            <p style="color: #7f8c8d; font-size: 12px;">Enviado automáticamente desde VERSATIL FRESH BOUTIQUE</p>
          </div>
        `;
      }

      const emailRequest = {
        to: [{ email: data.toEmail }],
        sender: { 
          email: "nadabrayan@gmail.com",  // Tu email verificado en Brevo
          name: "VERSATIL FRESH BOUTIQUE - Reportes" 
        },
        subject: data.subject || `Reporte de Caja - ${data.fileName}`,
        htmlContent: htmlBody,
        attachment: [{
          content: data.pdfBase64,
          name: data.fileName,
        }],
      };

      await brevoClient.transactionalEmails.sendTransacEmail(emailRequest);
      
      functions.logger.info(`✅ Email enviado a ${data.toEmail}: ${data.fileName}`);
      
      return { success: true, message: "Email enviado correctamente" };
    } catch (error: any) {
      functions.logger.error("❌ Error Brevo:", error);
      
      const message = error?.response?.body?.message || error?.message || "Error enviando email";
      throw new functions.https.HttpsError("internal", `Error Brevo: ${message}`);
    }
  }
);

// Función test (llamar desde consola Firebase)
export const testEmail = functions.https.onRequest(async (req, res) => {
  if (!brevoClient) {
    res.status(500).send("Brevo no configurado");
    return;
  }
  try {
    await brevoClient.transactionalEmails.sendTransacEmail({
      to: [{ email: "nadabrayan@gmail.com" }],
      sender: { email: "nadabrayan@gmail.com", name: "VERSATIL FRESH BOUTIQUE Test" },
      subject: "Test Email - VERSATIL FRESH BOUTIQUE POS + Brevo",
      htmlContent: "<p>✅ Test de envío automático desde Firebase Functions + Brevo</p>",
    });
    res.send("✅ Email de prueba enviado a nadabrayan@gmail.com");
  } catch (error: any) {
    functions.logger.error("Test error:", error);
    res.status(500).send("Error: " + (error?.response?.body?.message || error?.message));
  }
});