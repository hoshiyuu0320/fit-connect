import { describe, it, expect } from 'vitest'
import {
  splitFragment,
  isExternalUrl,
  extractStoragePath,
  noteFileName,
  isNoteFilePdf,
} from './storagePaths'

const PROJECT_URL = 'https://viribpvnpgtgtmeulcmx.supabase.co'

describe('splitFragment', () => {
  it('フラグメントなしの値はそのまま返す', () => {
    expect(splitFragment('abc/def.jpg')).toEqual({ base: 'abc/def.jpg', fragment: null })
  })

  it('パス#エンコード済みファイル名 を分離する', () => {
    const value = `abc/1234_file.pdf#${encodeURIComponent('提案書.pdf')}`
    expect(splitFragment(value)).toEqual({
      base: 'abc/1234_file.pdf',
      fragment: encodeURIComponent('提案書.pdf'),
    })
  })

  it('レガシーのフルURL#ファイル名 も分離できる', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/client-notes/t/c/1_a.pdf#a.pdf`
    expect(splitFragment(url)).toEqual({
      base: `${PROJECT_URL}/storage/v1/object/public/client-notes/t/c/1_a.pdf`,
      fragment: 'a.pdf',
    })
  })

  it('最初の # のみで分離する', () => {
    expect(splitFragment('a.jpg#x#y')).toEqual({ base: 'a.jpg', fragment: 'x#y' })
  })
})

describe('isExternalUrl', () => {
  it('Google の外部URLは true', () => {
    expect(isExternalUrl('https://lh3.googleusercontent.com/a/xyz=s96-c')).toBe(true)
  })

  it('Supabase Storage の公開URLは false', () => {
    expect(
      isExternalUrl(`${PROJECT_URL}/storage/v1/object/public/client-avatars/uid/avatar.jpg`),
    ).toBe(false)
  })

  it('Supabase Storage の署名URLは false', () => {
    expect(
      isExternalUrl(`${PROJECT_URL}/storage/v1/object/sign/message-photos/uid/a.jpg?token=x`),
    ).toBe(false)
  })

  it('バケット相対パスは false（URLではない）', () => {
    expect(isExternalUrl('uid/avatar.jpg')).toBe(false)
  })

  it('http（非https）の外部URLも true', () => {
    expect(isExternalUrl('http://example.com/image.png')).toBe(true)
  })
})

describe('extractStoragePath', () => {
  it('null / 空文字は null', () => {
    expect(extractStoragePath(null, 'message-photos')).toBeNull()
    expect(extractStoragePath(undefined, 'message-photos')).toBeNull()
    expect(extractStoragePath('', 'message-photos')).toBeNull()
  })

  it('バケット相対パスはそのまま返す', () => {
    expect(extractStoragePath('9d1ecf80-x/bad437a6-y.jpg', 'message-photos')).toBe(
      '9d1ecf80-x/bad437a6-y.jpg',
    )
  })

  it('パスの # フラグメントを除去する', () => {
    expect(
      extractStoragePath(`t/c/1234_report.pdf#${encodeURIComponent('報告書.pdf')}`, 'client-notes'),
    ).toBe('t/c/1234_report.pdf')
  })

  it('レガシーの公開URLからパスを抽出する', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/message-photos/trainer/client/1_a.jpg`
    expect(extractStoragePath(url, 'message-photos')).toBe('trainer/client/1_a.jpg')
  })

  it('署名URL（/object/sign/）からもパスを抽出する', () => {
    const url = `${PROJECT_URL}/storage/v1/object/sign/client-notes/t/c/1_a.pdf?token=xyz`
    expect(extractStoragePath(url, 'client-notes')).toBe('t/c/1_a.pdf')
  })

  it('URLのクエリ（Mobile レガシーの ?t=）を除去する', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/client-avatars/uid/avatar.jpg?t=1699999999`
    expect(extractStoragePath(url, 'client-avatars')).toBe('uid/avatar.jpg')
  })

  it('URLのクエリとフラグメントを両方除去する', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/client-notes/t/c/1_a.pdf?download=1#a.pdf`
    expect(extractStoragePath(url, 'client-notes')).toBe('t/c/1_a.pdf')
  })

  it('URL内のパーセントエンコードを復元する', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/client-notes/t/c/1_%E8%B3%87%E6%96%99.pdf`
    expect(extractStoragePath(url, 'client-notes')).toBe('t/c/1_資料.pdf')
  })

  it('外部URL（Google）は null', () => {
    expect(
      extractStoragePath('https://lh3.googleusercontent.com/a/xyz=s96-c', 'client-avatars'),
    ).toBeNull()
  })

  it('別バケットのURLは null', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/client-avatars/uid/avatar.jpg`
    expect(extractStoragePath(url, 'message-photos')).toBeNull()
  })

  it('バケット直下（パス空）のURLは null', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/message-photos/`
    expect(extractStoragePath(url, 'message-photos')).toBeNull()
  })

  it('フラグメントのみの値は null', () => {
    expect(extractStoragePath('#file.pdf', 'client-notes')).toBeNull()
  })
})

describe('noteFileName', () => {
  it('フラグメントに元ファイル名があればデコードして返す', () => {
    const value = `t/c/1234_file.pdf#${encodeURIComponent('提案書.pdf')}`
    expect(noteFileName(value)).toBe('提案書.pdf')
  })

  it('不正なパーセントエンコードのフラグメントはそのまま返す', () => {
    expect(noteFileName('t/c/1_a.pdf#%E0%A4%A')).toBe('%E0%A4%A')
  })

  it('フラグメントなしはパス末尾からタイムスタンププレフィックスを除いて返す', () => {
    expect(noteFileName('t/c/1699999999_report.pdf')).toBe('report.pdf')
  })

  it('数字プレフィックスがない場合はファイル名をそのまま返す', () => {
    expect(noteFileName('t/c/photo.png')).toBe('photo.png')
  })

  it('レガシーのフルURLからもファイル名を抽出する', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/client-notes/t/c/1699999999_a.pdf`
    expect(noteFileName(url)).toBe('a.pdf')
  })
})

describe('isNoteFilePdf', () => {
  it('パスの .pdf は true', () => {
    expect(isNoteFilePdf('t/c/1_report.pdf')).toBe(true)
  })

  it('大文字拡張子 .PDF も true', () => {
    expect(isNoteFilePdf('t/c/1_REPORT.PDF')).toBe(true)
  })

  it('画像パスは false', () => {
    expect(isNoteFilePdf('t/c/1_photo.jpg')).toBe(false)
  })

  it('フラグメント側に .pdf があってもパスが画像なら false', () => {
    expect(isNoteFilePdf(`t/c/1_photo.jpg#${encodeURIComponent('元は.pdf')}`)).toBe(false)
  })

  it('レガシーのフルURL（#フラグメント付き）でも判定できる', () => {
    const url = `${PROJECT_URL}/storage/v1/object/public/client-notes/t/c/1_a.pdf#a.pdf`
    expect(isNoteFilePdf(url)).toBe(true)
  })
})
