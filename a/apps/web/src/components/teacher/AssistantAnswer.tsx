import { } from 'react'

export function AssistantAnswer({ text }: { text: string }) {
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
  const renderInline = (value: string) => value.split(/(\*\*[^*]+\*\*)/g).map((part, index) => part.startsWith('**') && part.endsWith('**') ? <strong key={index}>{part.slice(2, -2)}</strong> : part)
  return <div className="assistant-answer space-y-3 text-sm leading-6">{lines.map((line, index) => {
    if (/^\|?\s*-{2,}/.test(line)) return null
    if (line.startsWith('## ')) return <h3 key={index} className="pt-2 text-base font-bold text-[var(--ink)]">{renderInline(line.replace(/^##\s+/, ''))}</h3>
    if (line.startsWith('- ')) return <p key={index} className="pl-4 text-[var(--muted)] before:mr-2 before:content-['•']">{renderInline(line.slice(2))}</p>
    if (line.startsWith('|')) {
      const cells = line.split('|').slice(1, -1).map((cell) => cell.trim())
      return <div key={index} className="grid grid-cols-4 gap-3 border-b border-[var(--line)] py-2 text-xs text-[var(--muted)]">{cells.map((cell, cellIndex) => <span key={cellIndex} className={index === 0 ? 'font-bold uppercase tracking-wide text-[var(--ink)]' : ''}>{renderInline(cell)}</span>)}</div>
    }
    return <p key={index}>{renderInline(line)}</p>
  })}</div>
}
