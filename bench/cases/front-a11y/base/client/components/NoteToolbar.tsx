import { PencilIcon } from './icons.tsx';

interface NoteToolbarProps {
  onEdit: () => void;
}

export function NoteToolbar({ onEdit }: NoteToolbarProps) {
  return (
    <div className="note-toolbar">
      <button type="button" className="icon-button" aria-label="Edit note" onClick={onEdit}>
        <PencilIcon aria-hidden="true" />
      </button>
    </div>
  );
}
