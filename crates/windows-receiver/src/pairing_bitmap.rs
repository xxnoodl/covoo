//! Uncompressed QR bitmap for the native plug-in view, including quiet zone.
pub fn encode(qr: &qrcode::QrCode) -> Vec<u8> {
    let scale = 4;
    let width = (qr.width() + 8) * scale;
    let stride = (width * 3 + 3) & !3;
    let size = 54 + stride * width;
    let mut bitmap = vec![255; size];
    bitmap[..54].fill(0);
    bitmap[..2].copy_from_slice(b"BM");
    for (offset, value) in [
        (2, size),
        (10, 54),
        (14, 40),
        (18, width),
        (22, width),
        (34, stride * width),
    ] {
        bitmap[offset..offset + 4].copy_from_slice(&(value as u32).to_le_bytes());
    }
    bitmap[26..28].copy_from_slice(&1u16.to_le_bytes());
    bitmap[28..30].copy_from_slice(&24u16.to_le_bytes());
    for y in 0..width {
        for x in 0..width {
            let (column, row) = (x / scale, y / scale);
            if column >= 4
                && row >= 4
                && column < qr.width() + 4
                && row < qr.width() + 4
                && qr[(column - 4, row - 4)] == qrcode::Color::Dark
            {
                let offset = 54 + (width - y - 1) * stride + x * 3;
                bitmap[offset..offset + 3].fill(0);
            }
        }
    }
    bitmap
}

#[cfg(test)]
mod tests {
    #[test]
    fn bitmap_has_exact_size_and_white_quiet_zone() {
        let qr = qrcode::QrCode::new(b"covoo test").unwrap();
        let bytes = super::encode(&qr);
        assert_eq!(&bytes[..2], b"BM");
        assert_eq!(
            u32::from_le_bytes(bytes[2..6].try_into().unwrap()) as usize,
            bytes.len()
        );
        let width = u32::from_le_bytes(bytes[18..22].try_into().unwrap()) as usize;
        assert_eq!(width, (qr.width() + 8) * 4);
        assert!(bytes[54..54 + width * 3].iter().all(|v| *v == 255));
        assert!(bytes[54..].contains(&0));
    }
}
