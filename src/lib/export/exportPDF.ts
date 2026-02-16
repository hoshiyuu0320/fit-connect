import jsPDF from 'jspdf'
import html2canvas from 'html2canvas'

interface ExportPDFParams {
  clientName: string
  startDate: string  // YYYY-MM-DD
  endDate: string    // YYYY-MM-DD
  stats: {
    latestWeight: number | null
    weightChange: number | null
    mealCount: number
    exerciseCount: number
    totalExerciseMinutes: number
    avgCaloriesPerDay: number | null
  }
  chartElementId: string  // html2canvas でキャプチャするDOM要素のid
}

/**
 * レポートデータをPDF形式でエクスポートする関数
 * html2canvasで指定されたDOM要素をキャプチャしてPDFに変換する
 */
export async function exportPDF(params: ExportPDFParams): Promise<void> {
  const { clientName, startDate, endDate, chartElementId } = params

  // キャプチャ対象の要素を取得
  const element = document.getElementById(chartElementId)
  if (!element) {
    throw new Error(`Element with id "${chartElementId}" not found`)
  }

  // PDF出力時に非表示にする要素を一時的に隠す
  const hiddenElements = element.querySelectorAll('[data-pdf-hide]')
  hiddenElements.forEach((el) => {
    ;(el as HTMLElement).style.display = 'none'
  })

  // html2canvasで高解像度キャプチャ
  let canvas: HTMLCanvasElement
  try {
    canvas = await html2canvas(element, {
      scale: 2,           // 高解像度化（2倍）
      useCORS: true,      // 外部画像のCORS対応
      backgroundColor: '#ffffff',  // 背景色を明示的に指定
    })
  } finally {
    // キャプチャ後に非表示要素を復元
    hiddenElements.forEach((el) => {
      ;(el as HTMLElement).style.display = ''
    })
  }

  // canvasをJPEG画像に変換
  const imgData = canvas.toDataURL('image/jpeg', 0.95)

  // jsPDFインスタンス作成（A4サイズ、縦向き）
  const pdf = new jsPDF('p', 'mm', 'a4')

  // A4サイズ（幅210mm、高さ297mm）
  const pageWidth = 210
  const pageHeight = 297
  const margin = 10  // 上下左右マージン

  // 利用可能な幅と高さ（マージン除く）
  const availableWidth = pageWidth - margin * 2
  const availableHeight = pageHeight - margin * 2

  // 画像の元のサイズ
  const imgWidth = canvas.width
  const imgHeight = canvas.height

  // 画像の縦横比を保ったまま、A4幅に収まるようにスケーリング
  const scaledWidth = availableWidth
  const scaledHeight = (imgHeight * scaledWidth) / imgWidth

  // 画像が1ページに収まる場合
  if (scaledHeight <= availableHeight) {
    pdf.addImage(imgData, 'JPEG', margin, margin, scaledWidth, scaledHeight)
  } else {
    // 画像が複数ページにわたる場合は分割
    let currentY = 0
    let pageCount = 0

    while (currentY < scaledHeight) {
      if (pageCount > 0) {
        pdf.addPage()
      }

      // 現在のページに表示する画像の高さ
      const remainingHeight = scaledHeight - currentY
      const heightForThisPage = Math.min(availableHeight, remainingHeight)

      // ソース画像から切り取る位置とサイズを計算
      const sourceY = (currentY / scaledHeight) * imgHeight
      const sourceHeight = (heightForThisPage / scaledHeight) * imgHeight

      // canvas から部分的に切り取り
      const tempCanvas = document.createElement('canvas')
      tempCanvas.width = imgWidth
      tempCanvas.height = sourceHeight

      const tempCtx = tempCanvas.getContext('2d')
      if (tempCtx) {
        tempCtx.drawImage(
          canvas,
          0, sourceY, imgWidth, sourceHeight,  // ソースの切り取り位置とサイズ
          0, 0, imgWidth, sourceHeight         // 描画先の位置とサイズ
        )

        const pageImgData = tempCanvas.toDataURL('image/jpeg', 0.95)
        pdf.addImage(pageImgData, 'JPEG', margin, margin, scaledWidth, heightForThisPage)
      }

      currentY += heightForThisPage
      pageCount++
    }
  }

  // PDFをダウンロード
  const filename = `report_${clientName}_${startDate}_${endDate}.pdf`
  pdf.save(filename)
}
