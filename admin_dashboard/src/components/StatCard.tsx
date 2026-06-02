import { Card } from './ui';
import { formatNumber } from '../lib/utils';

export function StatCard(props: {
  label: string;
  value: number | string;
  detail?: string;
}) {
  return (
    <Card className="p-4">
      <div className="text-sm font-medium text-slate-500">{props.label}</div>
      <div className="mt-2 text-2xl font-semibold text-ink">
        {typeof props.value === 'number' ? formatNumber(props.value) : props.value}
      </div>
      {props.detail ? <div className="mt-1 text-xs text-slate-500">{props.detail}</div> : null}
    </Card>
  );
}
