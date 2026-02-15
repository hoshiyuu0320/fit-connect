import { supabase } from '@/lib/supabase';
import { UpdateTicketParams } from '@/types/client';

// snake_case形式（SessionModalとの後方互換性）
type UpdateTicketParamsLegacy = {
  id: string;
  remaining_sessions?: number;
  ticket_name?: string;
  ticket_type?: string;
  total_sessions?: number;
  valid_from?: string;
  valid_until?: string;
};

export const updateTicket = async (params: UpdateTicketParams | UpdateTicketParamsLegacy) => {
  const updateData: Record<string, unknown> = {};

  // camelCase → snake_case 変換 (新形式)
  if ('ticketName' in params && params.ticketName !== undefined) {
    updateData.ticket_name = params.ticketName;
  }
  if ('ticketType' in params && params.ticketType !== undefined) {
    updateData.ticket_type = params.ticketType;
  }
  if ('totalSessions' in params && params.totalSessions !== undefined) {
    updateData.total_sessions = params.totalSessions;
  }
  if ('remainingSessions' in params && params.remainingSessions !== undefined) {
    updateData.remaining_sessions = params.remainingSessions;
  }
  if ('validFrom' in params && params.validFrom !== undefined) {
    updateData.valid_from = params.validFrom;
  }
  if ('validUntil' in params && params.validUntil !== undefined) {
    updateData.valid_until = params.validUntil;
  }

  // snake_case そのまま（後方互換性: SessionModal用）
  if ('remaining_sessions' in params && params.remaining_sessions !== undefined) {
    updateData.remaining_sessions = params.remaining_sessions;
  }
  if ('ticket_name' in params && params.ticket_name !== undefined) {
    updateData.ticket_name = params.ticket_name;
  }
  if ('ticket_type' in params && params.ticket_type !== undefined) {
    updateData.ticket_type = params.ticket_type;
  }
  if ('total_sessions' in params && params.total_sessions !== undefined) {
    updateData.total_sessions = params.total_sessions;
  }
  if ('valid_from' in params && params.valid_from !== undefined) {
    updateData.valid_from = params.valid_from;
  }
  if ('valid_until' in params && params.valid_until !== undefined) {
    updateData.valid_until = params.valid_until;
  }

  const { data, error } = await supabase
    .from('tickets')
    .update(updateData)
    .eq('id', params.id)
    .select()
    .single();

  if (error) {
    console.error('Error updating ticket:', error);
    throw error;
  }

  return data;
};
